# BookVault 3.0.0

Biblioteca visual para KOReader, feita para organizar uma biblioteca pessoal em um mosaico de capas reais sem substituir globalmente o FileManager, FileChooser, ReaderUI ou CoverBrowser.

## Recursos

- Mosaico real de capas usando os componentes atuais do CoverBrowser/MosaicMenu do KOReader.
- Categorias: Todos, Lendo, Em espera, Concluídos e Não iniciados.
- Coleções nativas do KOReader.
- Pesquisa visível na barra superior, por nome do arquivo e, quando disponível, título/autor dos metadados.
- Ordenação visível na barra superior por título, autor, mais recentes, modificados recentemente, tamanho e páginas, com direção persistente.
- Ordem personalizada persistente por status e por coleção.
- Grade de capas personalizável para retrato e paisagem.
- Identidade visual BookVault com PNGs leves e transparentes.
- Barra superior compatível com gerações do KOReader que não exibem `custom_title_bar`.
- Paginação e indicadores de progresso/status preservados pelo MosaicMenu nativo.
- Senha numérica com salt/hash.
- Proteção de pastas integrada ao File Browser por instância, sem monkey patch global das classes do KOReader.
- Privacidade independente da proteção, com `Privacidade: ON/OFF`.
- Seleção múltipla e ações em lote.
- Menu contextual por livro.
- Informações completas do livro reutilizando o BookInfo nativo do KOReader.
- Edição de metadados e capas pela infraestrutura nativa do KOReader.
- Busca de capas sob demanda no Google Imagens.
- Adicionar/remover livros de coleções diretamente pelo BookVault.
- Ações de plugins compatíveis.
- Renomear, copiar, mover, excluir e abrir localização pelo menu do livro.

## 3.0.0 — ações, metadados, privacidade e proteção

A nova camada de ações fica isolada em `bookvault_actions.lua`, preservando o núcleo visual estável. Operações de rede para capas só são executadas quando solicitadas pelo usuário; o scan normal da biblioteca não faz buscas externas.

A privacidade e a proteção são conceitos diferentes: privacidade controla visibilidade no BookVault; proteção exige senha para acessar/navegar em pastas protegidas no File Browser quando o BookVault estiver carregado nessa instância.

## Estabilidade

A integração visual continua lazy e por instância. O BookVault não substitui globalmente FileManager, FileChooser, ReaderUI ou CoverBrowser.

Se os módulos do CoverBrowser não estiverem disponíveis, o BookVault usa o BookList padrão em vez de falhar no carregamento.

A lógica visual continua usando `BookInfoManager`/`MosaicMenu` do KOReader, incluindo cache de capas, progresso e indicadores nativos.

## AppStore

O repositório mantém a estrutura de plugin KOReader e os tópicos de descoberta usados pela AppStore comunitária. A instalação pode usar o branch `main`; a AppStore mantém cache local e pode exigir atualização/refresh do catálogo antes de mostrar uma nova versão.
