import 'dart:convert';
import 'dart:ui' show Locale;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// ============================================================================
/// SERVIÇO DE LOCALIZAÇÃO E GEOCODIFICAÇÃO (LOCATION SERVICE)
/// ============================================================================
/// Módulo responsável pelo gerenciamento de permissões de hardware, captura de 
/// coordenadas geográficas (GPS), geocodificação reversa e consulta de CEP (ViaCEP).

/// Provider global Riverpod para injeção de dependência da classe [LocationService].
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Modelo DTO para agrupar os dados de endereço (GPS e ViaCEP)
class DadosEndereco {
  final String? cep;
  final String? logradouro;
  final String? bairro;
  final String? cidade;
  final String? uf;

  DadosEndereco({
    this.cep,
    this.logradouro,
    this.bairro,
    this.cidade,
    this.uf,
  });

  /// Getter utilitário para manter compatibilidade com o diálogo T07 do Flutter
  String get logradouroComNumero => logradouro ?? '';
}

class LocationService {
  /// Instância do geocoding (a partir da v5.0.0 os métodos ficam na classe
  /// [Geocoding] e não existem mais como funções de nível superior).
  /// O locale pt_BR faz o endereço retornar em português do Brasil.
  final Geocoding _geocoding = Geocoding(locale: const Locale('pt', 'BR'));

  /// Realiza a busca de endereço a partir de um CEP informado utilizando a API do ViaCEP.
  Future<DadosEndereco?> buscarEnderecoPorCep(String cep) async {
    final cepLimpo = cep.replaceAll(RegExp(r'\D'), '');

    if (cepLimpo.length != 8) return null;

    final url = Uri.parse('https://viacep.com.br/ws/$cepLimpo/json/');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados.containsKey('erro') && dados['erro'] == true) {
          throw Exception('CEP não encontrado.');
        }

        return DadosEndereco(
          cep: dados['cep'],
          logradouro: dados['logradouro'],
          bairro: dados['bairro'],
          cidade: dados['localidade'],
          uf: dados['uf'],
        );
      } else {
        throw Exception('Falha ao conectar ao serviço de busca de CEP.');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Obtém a localização atual e converte em dados de endereço via GPS.
  Future<DadosEndereco?> obterEnderecoAtual() async {
    // 1. Verificar se o serviço de localização (GPS) está habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('O serviço de GPS está desativado. Por favor, ative a localização do dispositivo.');
    }

    // 2. Verificar permissões de acesso à localização
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permissão de acesso à localização negada.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('As permissões de localização foram permanentemente negadas. Altere nas configurações do aparelho.');
    }

    // 3. Capturar a posição atual via GPS
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );

    // No ambiente Web, a biblioteca geocoding não converte coordenadas nativamente
    if (kIsWeb) {
      return DadosEndereco(
        logradouro: 'Localização GPS Web',
        bairro: 'Web',
        cidade: 'Navegador',
        uf: 'WEB',
      );
    }

    // 4. Geocodificação reversa
    try {
      final List<Placemark> placemarks = await _geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;

        final String logradouro = [
          if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) place.thoroughfare,
          if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) place.subThoroughfare,
        ].join(', ');

        return DadosEndereco(
          cep: place.postalCode,
          logradouro: logradouro.isNotEmpty ? logradouro : place.name,
          bairro: place.subLocality,
          cidade: place.locality ?? place.subAdministrativeArea,
          uf: place.administrativeArea,
        );
      }
    } catch (e) {
      return DadosEndereco(
        logradouro: 'Endereço não identificado',
        bairro: null,
        cidade: null,
        uf: null,
      );
    }

    return null;
  }
}