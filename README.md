# BookVault 2.3.0

Biblioteca visual para KOReader, feita para organizar uma biblioteca pessoal em um mosaico de capas reais sem substituir globalmente o FileManager, FileChooser, ReaderUI ou CoverBrowser.

## Recursos

- Mosaico real de capas usando os componentes atuais do CoverBrowser/MosaicMenu do KOReader.
- Categorias: Todos, Lendo, Em espera, Concluídos e Não iniciados.
- Coleções nativas do KOReader em modo somente leitura.
- Pesquisa visível na barra superior, por nome do arquivo e, quando disponível, título/autor dos metadados.
- Ordenação visível na barra superior por título, autor, mais recentes, modificados recentemente, tamanho e páginas.
- Ordem personalizada persistente por status e por coleção, com mover para cima, baixo, início e fim.
- Ordenação escolhida persistente por visualização.
- Grade de capas personalizável para retrato e paisagem, com 2–8 colunas/linhas, sem substituir o MosaicMenu.
- Identidade visual BookVault opcional e detalhe lunar opcional na barra.
- Paginação e indicadores de progresso/status preservados pelo MosaicMenu nativo.
- Senha numérica com salt/hash.
- Pastas protegidas e conteúdo privado.
- Conteúdo privado ocultado nas visualizações do BookVault até desbloqueio.

## Estabilidade

A integração visual é carregada de forma lazy e cada visualização recebe os métodos do CoverMenu/MosaicMenu apenas na própria instância. O plugin não instala monkey patches globais no FileChooser, FileManager, ReaderUI ou CoverBrowser.

Se os módulos do CoverBrowser não estiverem disponíveis, o BookVault usa o BookList padrão em vez de falhar no carregamento.

A lógica de capas usa `BookInfoManager`/`MosaicMenu` do KOReader, incluindo cache de capas, progresso e indicadores nativos. O BookVault não altera os arquivos dos livros para implementar pesquisa, ordenação, grade ou coleções.

## Privacidade e segurança

A proteção do BookVault controla o acesso pelas interfaces do plugin. Ela não é criptografia de arquivos nem impede que outro componente do sistema acesse diretamente os arquivos.

## Compatibilidade

A versão 2.3.0 acompanha as APIs atuais do KOReader usadas por `Menu`, `TitleBar`, `BookList`, `CoverMenu`, `MosaicMenu` e `BookInfoManager`. Como componentes internos do KOReader podem mudar entre versões, o teste final deve ser feito no dispositivo com a mesma versão do KOReader usada pelo usuário.

## AppStore

O repositório mantém a estrutura de plugin KOReader e os tópicos de descoberta usados pela AppStore comunitária. A instalação pode usar o branch `main`; uma release do GitHub não é necessária para a descoberta pelo catálogo.
