# AgiLista — Seu Assistente de Compras em Tempo Real
**Planeje. Compre. Controle.**

---

**Curso Técnico em Desenvolvimento de Sistemas — Instituto Federal do Piauí (IFPI)**  
**Turma:** 386 - Noite  
**Disciplinas e Docentes:**
- **Projeto Integrador** — Prof. Adalton Sena
- **Programação para Dispositivos Móveis** — Prof. Otilio Paulo
- **Programação Web Back-end** — Prof. Rogério Silva

**Equipe (Grupo ÁgiLista):** Daniel de C. Santos, André Ferreira, Rodrigo Fernandes e Maria Luiza  
**Versão:** 1.0 (Outubro – Dezembro/2026)

---

## 1. Visão Geral do Sistema

O **AgiLista** é um aplicativo móvel desenvolvido para atuar como assistente de compras em tempo real. A solução acompanha o consumidor em todas as etapas do processo: planejamento prévio de listas, execução presencial no supermercado com controle orçamentário rígido e consulta posterior de histórico e inteligência de preços.

O projeto adota a arquitetura **Offline-First**, permitindo o funcionamento completo das 21 telas locais via banco de dados SQLite, com sincronização em nuvem via API RESTful quando houver conectividade.

## 2. Stack Tecnológica Oficial

- **Frontend Mobile:** Flutter / Dart (Arquitetura Offline-First)
- **Banco de Dados Local:** SQLite (`sqflite`)
- **Backend API REST:** FastAPI / Python
- **Banco de Dados Nuvem:** PostgreSQL
- **Modelagem & Diagramação:** UML (Draw.io) e Mockups de Baixa Fidelidade

## 3. Mapeamento Completo das Funcionalidades (F01 – F18)

### Módulo de Acesso e Perfil
- **F01 — Cadastrar e Autenticar Usuário:** Permite ao consumidor criar uma conta e autenticar-se para acessar suas listas personalizadas e sincronizar dados (T01, T02).

### Módulo de Planejamento (Pré-Compra)
- **F02 — Criar e Gerenciar Lista de Compras:** Criação e edição do cabeçalho da lista enquanto mantiver o status `"Planejada"` (T04, T05).
- **F03 — Adicionar e Gerenciar Itens Planejados na Lista:** Inclusão livre de itens informando `nome_item_planejado`, `qtd_planejada` e `preco_estimado` (T04, T05).
- **F04 — Definir Orçamento Obrigatório da Lista:** Definição obrigatória do teto limite máximo `valor_orcamento` durante a fase de planejamento (T04).
- **F18 — Replicar Lista de Compras:** Criação de nova lista a partir de uma existente no histórico, preservando intacto o registro original e zerando dados de execução anteriores (T06).

### Módulo de Execução da Compra (Ponto de Venda)
- **F05 — Iniciar Compra e Registrar Localização do Estabelecimento:** Transição do status para `"Em Andamento"`, registro do estabelecimento e congelamento do planejamento/orçamento (T07).
- **F06 — Cadastrar e Gerenciar Produto no Carrinho:** Vínculo formal do produto do catálogo, definição de categoria e flag de recorrência (T10, T11).
- **F07 — Ler Código de Barras e Vincular Produto:** Leitura de código EAN via câmera do smartphone para busca ou cadastro imediato do produto (T09).
- **F08 — Calcular Automaticamente o Carrinho:** Processamento dinâmico do subtotal por item e do valor total acumulado em tempo real (T08, T13).
- **F09 — Aplicar Promoção por Quantidade:** Aplicação do preço promocional quando atingida a `qtd_minima_promocional` estabelecida (T15).
- **F10 — Registrar Produto Fora da Lista:** Inclusão de produtos não planejados adicionados diretamente ao carrinho no mercado (T14).
- **F11 — Controlar Orçamento em Tempo Real:** Comparação contínua entre total gasto e `valor_orcamento`, exibindo saldo restante e alertas de estouro (T08, T13).
- **F12 — Finalizar e Encerrar Compra:** Encerramento da compra, alteração do status para `"Concluída"` e consolidação dos dados gravados (T13, T16).

### Módulo Arquitetural e Dados
- **F13 — Arquitetura Funcional – Sincronização de Dados em Nuvem (Offline-First):** Execução local no SQLite e sincronização em lote/segundo plano via API FastAPI com o PostgreSQL na nuvem (T17).

### Módulo de Inteligência, Relatórios e Categorização (Pós-Compra)
- **F14 — Consultar Histórico de Compras e Comparativo:** Emissão e consulta de relatórios comparativos entre o planejado e o realizado (T18, T19).
- **F15 — Consultar Produtos Recorrentes:** Sugestão e consulta de itens frequentes combinando sinalização manual e algoritmo histórico (T20).
- **F16 — Consultar e Comparar Histórico de Preços:** Análise da variação histórica de preços de produtos entre diferentes estabelecimentos (T21).
- **F17 — Incluir e Alterar Categoria de Produtos:** Organização e classificação de produtos por categorias pré-configuradas ou personalizadas (T12).

## 4. Estrutura do Banco de Dados (Diagrama de Classes)

| Entidade | Atributos / Campos Oficiais |
| :--- | :--- |
| **Usuario** | `id_usuario`, `nome_usuario`, `email`, `senha_hash`, `tipo_plano`, `data_cadastro`, `ultima_sincronizacao` |
| **Lista** | `id_lista`, `usuario_id`, `nome_lista`, `valor_orcamento`, `valor_total_atual`, `status_lista`, `nome_estabelecimento`, `data_criacao`, `data_hora_inicio`, `data_hora_termino` |
| **ItemLista** | `id_item_lista`, `lista_id`, `produto_id`, `nome_item_planejado`, `qtd_planejada`, `preco_estimado`, `qtd_comprada`, `preco_unitario`, `subtotal_item`, `status_item`, `flag_promocao`, `qtd_minima_promocional`, `preco_promocional`, `flag_fora_da_lista` |
| **Produto** | `id_produto`, `categoria_id`, `codigo_barras`, `nome_produto`, `unidade_medida`, `flag_produto_recorrente` |
| **Categoria** | `id_categoria`, `nome_categoria`, `status_categoria` |

## 5. Mapeamento de Telas (T01 a T21)

1. **T01:** Login / Acesso
2. **T02:** Cadastro de Usuário
3. **T03:** Dashboard (Painel Principal)
4. **T04:** Criar / Editar Lista
5. **T05:** Minhas Listas (Planejadas)
6. **T06:** Minhas Listas (Concluídas / Replicar Lista)
7. **T07:** Iniciar Compra (Informar Estabelecimento)
8. **T08:** Minha Compra (Lista em Andamento)
9. **T09:** Adicionar Produto (Scanner EAN)
10. **T10:** Cadastro de Produto
11. **T11:** Consulta / Editar Produto
12. **T12:** Gestão de Categorias
13. **T13:** Minha Compra (Carrinho em Tempo Real)
14. **T14:** Item Fora da Lista
15. **T15:** Aplicar Promoção por Quantidade
16. **T16:** Finalizar Compra
17. **T17:** Status da Sincronização Nuvem (Sync)
18. **T18:** Histórico de Compras
19. **T19:** Relatório da Compra
20. **T20:** Produtos Recorrentes
21. **T21:** Histórico de Preços

## 6. Arquitetura de Pastas do App Mobile

```text
agilista_mobile/
├── assets/
│   └── images/
│       └── logo.png
├── lib/
│   ├── main.dart
│   ├── controllers/
│   │   ├── autenticacao_controller.dart
│   │   ├── categorias_controller.dart
│   │   ├── compras_controller.dart
│   │   ├── historico_contoller.dart
│   │   ├── listas_controller.dart
│   │   └── produtos_controller.dart
│   ├── models/
│   │   ├── categoria_model.dart
│   │   ├── item_lista_model.dart
│   │   ├── lista_model.dart
│   │   ├── produto_model.dart
│   │   └── usuario_model.dart
│   ├── nucleo/
│   │   ├── constantes/
│   │   │   ├── estados_constants.dart
│   │   │   └── status_constants.dart
│   │   ├── database/
│   │   │   └── app_database.dart
│   │   ├── tema/
│   │   │   └── app_theme.dart
│   │   └── utilitarios/
│   │       └── formatadores.dart
│   ├── repositories/
│   │   ├── autenticacao_repository.dart
│   │   ├── exclusao_repository.dart
│   │   ├── listas_repository.dart
│   │   └── produtos_repository.dart
│   ├── services/
│   │   ├── localizacao_service.dart
│   │   ├── sincronizacao_categorias_service.dart
│   │   ├── sincronizacao_listas_service.dart
│   │   └── sincronizacao_produtos_service.dart
│   └── views/
│       ├── autenticacao/
│       │   ├── t01_login_screen.dart
│       │   ├── t02_cadastro_usuario_screen.dart
│       │   └── t02a_perfil_usuario_screen.dart
│       ├── compras/
│       │   ├── t07_iniciar_compra_dialog.dart
│       │   ├── t08_t13_minha_compra_screen.dart
│       │   ├── t09_t14_t15_adicionar_produto_screen.dart
│       │   ├── t10_t11_cadastro_produtos_screen.dart
│       │   ├── t12_t22_cadastro_categoria_screen.dart
│       │   └── t16_finalizar_compra_screen.dart
│       ├── historico/
│       │   ├── t18_historico_screen.dart
│       │   ├── t19_relatorio_compra_screen.dart
│       │   ├── t20_produtos_recorrentes_screen.dart
│       │   └── t21_historico_preco_screen.dart
│       ├── listas/
│       │   ├── t03_home_screen.dart
│       │   ├── t04_criar_editar_lista_screen.dart
│       │   └── t05_t06_minhas_listas_screen.dart
│       └── widgets/
│           └── seletor_periodo_widget.dart
└── pubspec.yaml

