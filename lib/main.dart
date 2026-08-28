import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const RadioPXApp());

class RadioPXApp extends StatelessWidget {
  const RadioPXApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '📻 Rádio PX Digital',
      theme: ThemeData.dark(),
      home: const TelaPermissao(),
    );
  }
}

class TelaPermissao extends StatefulWidget {
  const TelaPermissao({super.key});
  @override
  State<TelaPermissao> createState() => _TelaPermissaoState();
}

class _TelaPermissaoState extends State<TelaPermissao> {
  bool temPermissao = false;

  @override
  void initState() {
    super.initState();
    verificarPermissao();
  }

  Future<void> verificarPermissao() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      setState(() => temPermissao = true);
    }
  }

  Future<void> pedirPermissao() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      setState(() => temPermissao = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (temPermissao) return const TelaLogin();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic, size: 80, color: Colors.amber),
              const SizedBox(height: 32),
              const Text('Permissão de Microfone', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Precisamos acessar seu microfone para falar no Rádio PX.', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: pedirPermissao,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16)),
                child: const Text('PERMITIR MICROFONE', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});
  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final TextEditingController _nomeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📻 Rádio PX Digital')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radio, size: 80, color: Colors.amber),
              const SizedBox(height: 32),
              const Text('Digite seu indicativo:', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              TextField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  hintText: 'Ex: Operador 01',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final nome = _nomeController.text.trim();
                  if (nome.isNotEmpty) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => TelaPrincipal(usuario: nome)),
                    );
                  }
                },
                child: const Text('ENTRAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TelaPrincipal extends StatefulWidget {
  final String usuario;
  const TelaPrincipal({super.key, required this.usuario});
  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  static const String ENDERECO = 'wss://957713a6-cd67-4271-95ad-fad3eb491b36-00-1xgeohyhb1rwi.reed.repl.co';
  
  int canal = 1;
  bool isFalando = false;
  String? falandoQuem;
  bool conectado = false;
  
  WebSocketChannel? socket;
  final AudioRecorder gravador = AudioRecorder();
  final AudioPlayer player = AudioPlayer();
  bool gravando = false;

  @override
  void initState() {
    super.initState();
    conectar();
  }

  void conectar() {
    socket = WebSocketChannel.connect(Uri.parse(ENDERECO));
    
    socket!.stream.listen((mensagem) {
      final dados = json.decode(mensagem);
      switch (dados['tipo']) {
        case 'USUARIO_ENTROU':
          setState(() => conectado = true);
          break;
        case 'FALANDO':
          setState(() {
            falandoQuem = dados['usuario'];
            conectado = true;
          });
          break;
        case 'SILENCIO':
        case 'USUARIO_SAIU':
          setState(() => falandoQuem = null);
          break;
        case 'AUDIO':
          final bytes = base64.decode(dados['dados']);
          player.play(BytesSource(bytes));
          break;
      }
    }, onError: (e) {
      setState(() => conectado = false);
    });

    socket!.ready.then((_) {
      setState(() => conectado = true);
      entrarNoCanal(canal);
    });
  }

  void entrarNoCanal(int num) {
    canal = num;
    socket?.sink.add(json.encode({'tipo': 'ENTRAR_CANAL', 'usuario': widget.usuario, 'canal': canal}));
  }

  Future<void> iniciarGravacao() async {
    if (falandoQuem != null) return;
    setState(() => isFalando = true);
    socket?.sink.add(json.encode({'tipo': 'FALANDO', 'usuario': widget.usuario}));

    gravando = true;
    const config = RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000);
    await gravador.startStream(config).then((stream) {
      stream.listen((dados) {
        if (!gravando) return;
        final base64Dados = base64.encode(dados);
        socket?.sink.add(json.encode({'tipo': 'AUDIO', 'usuario': widget.usuario, 'dados': base64Dados}));
      });
    });
  }

  Future<void> pararGravacao() async {
    gravando = false;
    setState(() => isFalando = false);
    await gravador.stop();
    socket?.sink.add(json.encode({'tipo': 'PAROU_FALAR'}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📻 Rádio PX — Canal $canal'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(widget.usuario, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Icon(conectado ? Icons.wifi : Icons.wifi_off, color: conectado ? Colors.green : Colors.red),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            conectado
                ? (falandoQuem != null ? '🔴 $falandoQuem está falando...' : '🟢 Canal Livre')
                : '⏳ Conectando...',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 40),

          GestureDetector(
            onLongPressStart: (_) => iniciarGravacao(),
            onLongPressEnd: (_) => pararGravacao(),
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: isFalando ? Colors.red : Colors.amber,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isFalando ? Icons.mic : Icons.mic_none, size: 60, color: Colors.black87),
                  const SizedBox(height: 8),
                  Text(
                    isFalando ? 'FALANDO...' : 'SEGURE PARA FALAR',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle, size: 40, color: Colors.amber),
                onPressed: () => setState(() {
                  canal = canal > 1 ? canal - 1 : 40;
                  entrarNoCanal(canal);
                }),
              ),
              Text('$canal', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.amber)),
              IconButton(
                icon: const Icon(Icons.add_circle, size: 40, color: Colors.amber),
                onPressed: () => setState(() {
                  canal = canal < 40 ? canal + 1 : 1;
                  entrarNoCanal(canal);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    socket?.sink.close();
    gravador.dispose();
    player.dispose();
    super.dispose();
  }
}
