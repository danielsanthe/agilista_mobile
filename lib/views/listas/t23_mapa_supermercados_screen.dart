import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../nucleo/constantes/status_constants.dart';
import '../../nucleo/tema/app_theme.dart';
import '../../controllers/listas_controller.dart';
import '../../models/lista_model.dart';
import '../../services/localizacao_service.dart';

/// ============================================================================
/// TELA T23 — MAPA (GOOGLE MAPS) COM LOCALIZAÇÃO ATUAL E SUPERMERCADOS FREQUENTADOS
/// ============================================================================
/// - Mostra a posição atual do dispositivo (GPS) via [LocationService].
/// - Exibe marcadores dos estabelecimentos já usados nas compras (listas em
///   andamento/concluídas), ordenados pela frequência de visitas.
/// - Ao tocar em um marcador, mostra o painel com a distância em linha reta e o
///   botão "Traçar rota", que abre o Google Maps com a rota a partir da posição atual.
///
/// Arquitetura Offline-First:
/// - Os estabelecimentos vêm do SQLite local (via [ListsController]); nenhuma
///   coluna nova no banco ou na API foi necessária.
/// - As coordenadas são obtidas por geocodificação do endereço salvo na lista e
///   ficam em cache durante a sessão. Sem internet, o mapa abre normalmente e os
///   marcadores aparecem quando a conexão voltar (ao reabrir a tela).
class MapaSupermercadosScreen extends ConsumerStatefulWidget {
  const MapaSupermercadosScreen({super.key});

  @override
  ConsumerState<MapaSupermercadosScreen> createState() =>
      _MapaSupermercadosScreenState();
}

/// Estabelecimento agrupado a partir do histórico de listas.
class _Supermercado {
  final String nome;
  final String consulta;

  /// Número de listas (compras) no estabelecimento; começa em 1 e é incrementado ao agrupar.
  int visitas = 1;

  _Supermercado({required this.nome, required this.consulta});
}

/// Supermercado selecionado no mapa (marcador tocado).
class _MercadoSelecionado {
  final String nome;
  final int visitas;
  final LatLng posicao;

  _MercadoSelecionado({required this.nome, required this.visitas, required this.posicao});
}

class _MapaSupermercadosScreenState
    extends ConsumerState<MapaSupermercadosScreen> {
  /// Posição inicial enquanto o GPS não responde (coordenadas do IFPI, como na aula).
  static const LatLng _posicaoInicial = LatLng(-5.0885440460, -42.8112380314);

  /// Máximo de estabelecimentos geocodificados por abertura (limita chamadas de rede).
  static const int _limiteSupermercados = 15;

  /// Cache de coordenadas por consulta de endereço (só guarda resultados válidos).
  static final Map<String, LatLng> _cacheCoordenadas = {};

  GoogleMapController? _controller;
  final Set<Marker> _marcadores = {};
  LatLng? _minhaPosicao;
  String? _avisoLocalizacao;
  bool _carregandoSupermercados = false;
  String _assinaturaProcessada = '';
  _MercadoSelecionado? _selecionado;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _localizarUsuario();
      _carregarSupermercados(ref.read(listsControllerProvider).value ?? []);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Captura a posição atual (GPS) e centraliza a câmera nela.
  Future<void> _localizarUsuario() async {
    try {
      final pos = await ref.read(locationServiceProvider).obterPosicaoAtual();
      if (!mounted) return;
      final minha = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _minhaPosicao = minha;
        _avisoLocalizacao = null;
      });
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(minha, 14));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _avisoLocalizacao = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  String? _texto(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Agrupa o histórico de listas por estabelecimento (ignora listas só planejadas).
  Map<String, _Supermercado> _agruparSupermercados(List<ListaModel> listas) {
    final mapa = <String, _Supermercado>{};
    for (final lista in listas) {
      if (lista.statusLista == StatusLista.planejada) continue;
      final nome = _texto(lista.nomeEstabelecimento);
      if (nome == null) continue;

      final consulta = [
        nome,
        _texto(lista.enderecoEstabelecimento),
        _texto(lista.bairro),
        _texto(lista.cidade),
        _texto(lista.uf),
      ].whereType<String>().join(', ');

      final chave = nome.toLowerCase();
      final existente = mapa[chave];
      if (existente != null) {
        existente.visitas++;
      } else {
        mapa[chave] = _Supermercado(nome: nome, consulta: consulta);
      }
    }
    return mapa;
  }

  /// Converte o endereço em coordenadas (com cache em memória).
  Future<LatLng?> _coordenadas(String consulta) async {
    final emCache = _cacheCoordenadas[consulta];
    if (emCache != null) return emCache;

    final c = await ref.read(locationServiceProvider).coordenadasDoEndereco(consulta);
    if (c == null) return null;
    final latLng = LatLng(c.latitude, c.longitude);
    _cacheCoordenadas[consulta] = latLng;
    return latLng;
  }

  /// Monta os marcadores dos supermercados mais frequentados.
  Future<void> _carregarSupermercados(List<ListaModel> listas) async {
    if (_carregandoSupermercados) return;

    final frequentes = _agruparSupermercados(listas);
    final assinatura = frequentes.values
        .map((s) => '${s.nome}|${s.consulta}|${s.visitas}')
        .join(';');
    if (assinatura == _assinaturaProcessada) return;
    _assinaturaProcessada = assinatura;

    setState(() => _carregandoSupermercados = true);

    final ordenados = frequentes.values.toList()
      ..sort((a, b) => b.visitas.compareTo(a.visitas));

    final novos = <Marker>{};
    var houveFalha = false;
    for (final s in ordenados.take(_limiteSupermercados)) {
      final posicao = await _coordenadas(s.consulta);
      if (!mounted) return;
      if (posicao == null) {
        houveFalha = true;
        continue;
      }

      novos.add(
        Marker(
          markerId: MarkerId('mercado_${s.nome.toLowerCase()}'),
          position: posicao,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: s.nome,
            snippet: s.visitas == 1 ? '1 compra' : '${s.visitas} compras',
          ),
          onTap: () => setState(() {
            _selecionado = _MercadoSelecionado(
              nome: s.nome,
              visitas: s.visitas,
              posicao: posicao,
            );
          }),
        ),
      );
    }

    if (!mounted) return;
    // Se algum endereço não foi localizado (ex.: sem internet), limpa a assinatura para
    // que a próxima tentativa (botão "Meus mercados" ou recarga das listas) refaça a busca.
    if (houveFalha) _assinaturaProcessada = '';
    setState(() {
      _marcadores
        ..clear()
        ..addAll(novos);
      _carregandoSupermercados = false;
    });
  }

  /// Ajusta a câmera para enquadrar todos os supermercados marcados.
  Future<void> _enquadrarSupermercados() async {
    if (_marcadores.isEmpty) {
      // Tenta localizar os supermercados novamente (útil quando a internet voltou)
      _carregarSupermercados(ref.read(listsControllerProvider).value ?? []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum supermercado localizado ainda. Conclua compras informando o '
            'estabelecimento e verifique a conexão com a internet.',
          ),
        ),
      );
      return;
    }

    final pontos = _marcadores.map((m) => m.position).toList();
    // Inclui a posição do usuário para a câmera mostrar você e os supermercados juntos
    if (_minhaPosicao != null) pontos.add(_minhaPosicao!);
    if (pontos.length == 1) {
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(pontos.first, 15));
      return;
    }

    final lats = pontos.map((p) => p.latitude);
    final lngs = pontos.map((p) => p.longitude);
    final limites = LatLngBounds(
      southwest: LatLng(lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b)),
      northeast: LatLng(lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b)),
    );
    await _controller?.animateCamera(CameraUpdate.newLatLngBounds(limites, 64));
  }

  /// Abre o Google Maps com a rota até o supermercado. Sem o parâmetro `origin`,
  /// o Google Maps usa a localização atual do aparelho como ponto de partida.
  Future<void> _abrirRota(LatLng destino) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${destino.latitude},${destino.longitude}',
      'travelmode': 'driving',
    });

    var abriu = false;
    try {
      abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }

    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Google Maps.')),
      );
    }
  }

  String _formatarDistancia(double metros) {
    if (metros < 1000) return '${metros.round()} m';
    return '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  /// Painel inferior com os dados do supermercado selecionado e o botão de rota.
  Widget _painelMercado(_MercadoSelecionado mercado) {
    final minha = _minhaPosicao;
    var detalhe = mercado.visitas == 1 ? '1 compra' : '${mercado.visitas} compras';
    if (minha != null) {
      final metros = Geolocator.distanceBetween(
        minha.latitude,
        minha.longitude,
        mercado.posicao.latitude,
        mercado.posicao.longitude,
      );
      detalhe += ' • ${_formatarDistancia(metros)} em linha reta';
    }

    return Material(
      color: AppTheme.surfaceWhite,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront_outlined, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mercado.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selecionado = null),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 12),
                child: Text(detalhe, style: const TextStyle(fontSize: 13)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _abrirRota(mercado.posicao),
                    icon: const Icon(Icons.directions),
                    label: const Text('Traçar rota'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recalcula os marcadores quando as listas do SQLite forem carregadas/sincronizadas
    ref.listen(listsControllerProvider, (anterior, proximo) {
      proximo.whenData(_carregarSupermercados);
    });

    return Scaffold(
      // AppBar idêntica à da tela Categoria: seta de voltar padrão (branca) + título em negrito
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: const Text(
          'Mapa',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _posicaoInicial,
              zoom: 12,
            ),
            onMapCreated: (controller) {
              _controller = controller;
              final minha = _minhaPosicao;
              if (minha != null) {
                controller.animateCamera(CameraUpdate.newLatLngZoom(minha, 14));
              }
            },
            // Reserva espaço embaixo para o botão "Meus mercados" não cobrir o zoom (+/-)
            padding: const EdgeInsets.only(bottom: 88),
            onTap: (_) {
              if (_selecionado != null) setState(() => _selecionado = null);
            },
            // Só habilita o ponto azul depois que a permissão foi concedida
            myLocationEnabled: _minhaPosicao != null,
            myLocationButtonEnabled: _minhaPosicao != null,
            markers: _marcadores,
          ),
          if (_carregandoSupermercados)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_avisoLocalizacao != null)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Card(
                color: AppTheme.surfaceWhite,
                child: ListTile(
                  leading: const Icon(Icons.location_off, color: AppTheme.statusDanger),
                  title: Text(
                    _avisoLocalizacao!,
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: TextButton(
                    onPressed: _localizarUsuario,
                    child: const Text('Tentar'),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _selecionado == null ? null : _painelMercado(_selecionado!),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: _enquadrarSupermercados,
        icon: const Icon(Icons.storefront_outlined),
        label: const Text('Meus mercados'),
      ),
    );
  }
}
