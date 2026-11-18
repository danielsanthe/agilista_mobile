/// ============================================================================
/// CONSTANTES DE UNIDADES FEDERATIVAS DO BRASIL (ESTADOS <-> SIGLAS UF)
/// ============================================================================
/// Fornece o mapeamento completo das 27 Unidades Federativas do Brasil para
/// normalizar retornos do GPS (Geocoding), formulários de endereço e payloads
/// enviados à API FastAPI (que exige sigla de exatamente 2 caracteres).
class EstadosConstants {
  EstadosConstants._();

  /// Mapa de siglas oficiais (UF) para o nome por extenso do estado.
  static const Map<String, String> siglasParaNome = {
    'AC': 'Acre',
    'AL': 'Alagoas',
    'AP': 'Amapá',
    'AM': 'Amazonas',
    'BA': 'Bahia',
    'CE': 'Ceará',
    'DF': 'Distrito Federal',
    'ES': 'Espírito Santo',
    'GO': 'Goiás',
    'MA': 'Maranhão',
    'MT': 'Mato Grosso',
    'MS': 'Mato Grosso do Sul',
    'MG': 'Minas Gerais',
    'PA': 'Pará',
    'PB': 'Paraíba',
    'PR': 'Paraná',
    'PE': 'Pernambuco',
    'PI': 'Piauí',
    'RJ': 'Rio de Janeiro',
    'RN': 'Rio Grande do Norte',
    'RS': 'Rio Grande do Sul',
    'RO': 'Rondônia',
    'RR': 'Roraima',
    'SC': 'Santa Catarina',
    'SP': 'São Paulo',
    'SE': 'Sergipe',
    'TO': 'Tocantins',
  };

  /// Mapa normalizado (em maiúsculas e sem acentos) do nome do estado ou sigla
  /// para a respectiva sigla oficial de 2 caracteres (UF).
  static const Map<String, String> nomeParaSigla = {
    'ACRE': 'AC',
    'AC': 'AC',
    'ALAGOAS': 'AL',
    'AL': 'AL',
    'AMAPA': 'AP',
    'AP': 'AP',
    'AMAZONAS': 'AM',
    'AM': 'AM',
    'BAHIA': 'BA',
    'BA': 'BA',
    'CEARA': 'CE',
    'CE': 'CE',
    'DISTRITO FEDERAL': 'DF',
    'DF': 'DF',
    'ESPIRITO SANTO': 'ES',
    'ES': 'ES',
    'GOIAS': 'GO',
    'GO': 'GO',
    'MARANHAO': 'MA',
    'MA': 'MA',
    'MATO GROSSO': 'MT',
    'MT': 'MT',
    'MATO GROSSO DO SUL': 'MS',
    'MS': 'MS',
    'MINAS GERAIS': 'MG',
    'MG': 'MG',
    'PARA': 'PA',
    'PA': 'PA',
    'PARAIBA': 'PB',
    'PB': 'PB',
    'PARANA': 'PR',
    'PR': 'PR',
    'PERNAMBUCO': 'PE',
    'PE': 'PE',
    'PIAUI': 'PI',
    'PI': 'PI',
    'RIO DE JANEIRO': 'RJ',
    'RJ': 'RJ',
    'RIO GRANDE DO NORTE': 'RN',
    'RN': 'RN',
    'RIO GRANDE DO SUL': 'RS',
    'RS': 'RS',
    'RONDONIA': 'RO',
    'RO': 'RO',
    'RORAIMA': 'RR',
    'RR': 'RR',
    'SANTA CATARINA': 'SC',
    'SC': 'SC',
    'SAO PAULO': 'SP',
    'SP': 'SP',
    'SERGIPE': 'SE',
    'SE': 'SE',
    'TOCANTINS': 'TO',
    'TO': 'TO',
  };

  /// Remove acentuação comum em português e converte para maiúsculas.
  static String _removerAcentos(String texto) {
    const comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
    const semAcento = 'AAAAAEEEEIIIIOOOOOUUUUCN';
    var resultado = texto.trim().toUpperCase();
    for (int i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }
    return resultado;
  }

  /// Converte qualquer descrição de estado (ex: "Piauí", "PIAUÍ", "pi", "State of Piauí")
  /// na sigla oficial de 2 letras (ex: "PI"). Retorna `null` se não for reconhecido.
  static String? normalizarUf(String? valorBruto) {
    if (valorBruto == null) return null;
    var limpo = _removerAcentos(valorBruto);
    if (limpo.isEmpty) return null;

    limpo = limpo
        .replaceFirst(RegExp(r'^ESTADO DO\s+'), '')
        .replaceFirst(RegExp(r'^ESTADO DE\s+'), '')
        .replaceFirst(RegExp(r'^ESTADO DA\s+'), '')
        .replaceFirst(RegExp(r'^STATE OF\s+'), '')
        .trim();

    if (nomeParaSigla.containsKey(limpo)) {
      return nomeParaSigla[limpo];
    }

    for (final entry in nomeParaSigla.entries) {
      if (entry.key.length > 2 && limpo.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }
}