# BookVault 2.5.0

Biblioteca visual para KOReader, feita para organizar uma biblioteca pessoal em um mosaico de capas reais sem substituir globalmente o FileManager, FileChooser, ReaderUI ou CoverBrowser.

## Recursos

- Mosaico real de capas usando os componentes atuais do CoverBrowser/MosaicMenu do KOReader.
- Categorias: Todos, Lendo, Em espera, Concluídos e Não iniciados.
- Coleções nativas do KOReader em modo somente leitura.
- Pesquisa visível na barra superior, por nome do arquivo e, quando disponível, título/autor dos metadados.
- Ordenação visível na barra superior por título, autor, mais recentes, modificados recentemente, tamanho e páginas, com ícone próprio do BookVault.
- Ordem personalizada persistente por status e por coleção, com mover para cima, baixo, início e fim.
- Ordenação escolhida persistente por visualização.
- Grade de capas personalizável para retrato e paisagem, com 2–8 colunas/linhas, sem substituir o MosaicMenu.
- Identidade visual BookVault opcional, com gatinho e detalhe lunar em PNG leve e transparente, sem emojis.
- Barra superior compatível com gerações do KOReader que não exibem `custom_title_bar`: os controles são montados sobre a barra nativa, preservando a navegação.
- Paginação e indicadores de progresso/status preservados pelo MosaicMenu nativo.
- Senha numérica com salt/hash.
- Pastas protegidas e conteúdo privado.
- Conteúdo privado ocultado nas visualizações do BookVault até desbloqueio.

## 2.5.0 — fechamento visual e compatibilidade

- Busca e ordenação passam a usar botões PNG próprios e leves.
- Gatinho + ordenação e lua são elementos visuais reais, não emojis.
- O controle de ordenação não depende exclusivamente do suporte de `right_icon`/`custom_title_bar` da versão do KOReader instalada.
- O bootstrap copia os PNGs para a pasta de ícones do KOReader antes do carregamento dos widgets e remove variantes SVG legadas que poderiam vencer a resolução do PNG.
- O ajuste da grade força o recálculo da dimensão do mosaico antes da atualização.
- Mosaico, pesquisa, ordenação, ordem personalizada, grade, coleções, progresso, senha e privacidade foram preservados.
- Nenhum monkey patch global foi reintroduzido.

## Estabilidade

A integração visual é carregada de forma lazy e cada visualização recebe os métodos do CoverMenu/MosaicMenu apenas na própria instância. O plugin não instala monkey patches globais no FileChooser, FileManager, ReaderUI ou CoverBrowser.

Se os módulos do CoverBrowser não estiverem disponíveis, o BookVault usa o BookList padrão em vez de falhar no carregamento.

A lógica de capas usa `BookInfoManager`/`MosaicMenu` do KOReader, incluindo cache de capas, progresso e indicadores nativos. O BookVault não altera os arquivos dos livros para implementar pesquisa, ordenação, grade ou coleções.

## Privacidade e segurança

A proteção do BookVault controla o acesso pelas interfaces do plugin. Ela não é criptografia de arquivos nem impede que outro componente do sistema acesse diretamente os arquivos.

## Compatibilidade

A versão 2.5.0 usa a barra nativa do BookList como base e adiciona uma camada de controles própria, reduzindo a dependência de diferenças entre versões do `TitleBar`. O mosaico continua usando `CoverMenu`, `MosaicMenu` e `BookInfoManager` de forma lazy e por instância.

## AppStore

O repositório mantém a estrutura de plugin KOReader e os tópicos de descoberta usados pela AppStore comunitária. A instalação pode usar o branch `main`; a AppStore mantém cache local e pode exigir atualização/refresh do catálogo antes de mostrar uma nova versão. 
