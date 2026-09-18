# BookVault 3.2.0

Biblioteca visual para KOReader, projetada para telas e-ink: monocromática, leve, minimalista e integrada às APIs nativas do KOReader.

## Interface

- Mosaico real de capas usando CoverBrowser/MosaicMenu do KOReader.
- Identidade visual BookVault em preto, branco e cinzas, com ícones PNG leves.
- Barra superior própria com identidade, busca, detalhe lunar, ordenação e configurações.
- Grade de capas personalizável para retrato e paisagem.
- Paginação e indicadores nativos de progresso/status preservados.
- Busca visível por nome do arquivo e, quando disponível, título/autor dos metadados.
- Ordenação por título, autor, acessados recentemente, modificados recentemente, tamanho e páginas, com direção persistente.
- Ordem personalizada persistente por status e coleção.
- Categorias: Todos, Lendo, Em espera, Concluídos e Não iniciados.

## Ações por livro

- Toque abre o livro.
- Pressão longa abre o menu contextual BookVault.
- Informações do livro usando o BookInfo nativo do KOReader.
- Edição de metadados pela tela nativa de informações do livro, inclusive campos personalizados suportados pelo KOReader.
- Adicionar capa quando não houver capa.
- Alterar capa quando já houver capa.
- Busca de capas no Google Imagens somente quando solicitada, com escolha do resultado antes da aplicação.
- Status de leitura.
- Coleções.
- Selecionar vários.
- Renomear.
- Copiar.
- Mover.
- Abrir localização.
- Excluir.
- Mais ações/plugins.

## Seleção múltipla

- Pressão longa entra no modo de seleção.
- Seleção/desseleção individual sem abrir livros.
- Abrir o primeiro selecionado.
- Alterar status.
- Adicionar/remover vários livros de coleções.
- Criar coleção.
- Mover vários.
- Copiar vários.
- Excluir vários.
- Sair do modo de seleção.
- A seleção é mantida apenas na tela ativa e não cria trabalho em segundo plano.

## Coleções

O BookVault reutiliza as coleções nativas do KOReader:

- visualizar coleções dentro do BookVault;
- adicionar/remover um livro;
- adicionar/remover vários livros;
- selecionar múltiplas coleções;
- criar uma coleção;
- preservar as coleções fora do BookVault.

## Privacidade

A privacidade é independente da proteção de pastas.

- **Privacidade: ON** — conteúdo marcado como privado fica oculto no BookVault.
- **Privacidade: OFF** — conteúdo privado pode ser revelado após autenticação.
- Ativar/desativar não exige senha para esconder novamente.
- A senha numérica usa salt/hash.
- Ao suspender/retomar o plugin, o estado desbloqueado é encerrado.

## Pastas protegidas

- Pastas protegidas exigem senha quando acessadas por interfaces do KOReader nas quais o BookVault está presente e pode instalar a proteção por instância.
- Subpastas são abrangidas pela regra de caminho.
- Proteção e privacidade são estados independentes.
- A integração evita substituir globalmente classes como WidgetContainer, BookList, FileManager ou FileChooser.

**Limite importante:** um plugin normal do KOReader não deve interceptar de forma global toda abertura de arquivo, SimpleUI e todas as interfaces de terceiros sem hooks globais/user patches. O BookVault prioriza estabilidade e não usa monkey patches globais para tentar simular essa cobertura.

## Operações de arquivos

Renomear, mover e copiar usam as rotinas de metadados do KOReader quando disponíveis, incluindo a atualização/migração do sidecar e da leitura. Excluir também limpa os metadados associados pela infraestrutura nativa antes de remover o arquivo.

## Desempenho e estabilidade

- Nenhuma busca de capa durante o scan normal.
- Rede carregada apenas quando a busca de capa é solicitada.
- Módulos visuais pesados são carregados sob demanda.
- Cache e metadados são consultados somente quando necessários.
- O mosaico continua usando componentes nativos do KOReader.
- Nenhum monkey patch global é usado.
- A falha de módulos visuais não impede o carregamento: há fallback para BookList padrão.
- Ações são instaladas diretamente na classe BookVault e nos menus criados pelo próprio BookVault.
- Operações potencialmente destrutivas pedem confirmação.
- Alterações de arquivo só acontecem após ação explícita do usuário.

## AppStore

O repositório mantém a estrutura de plugin KOReader e os arquivos de metadados necessários para descoberta pela AppStore comunitária. A versão é publicada no branch padrão para manter a descoberta e atualização do plugin.

Após atualizar pelo AppStore, se uma versão antiga continuar em cache, use **Refresh cache/Atualizar** e reinicie o KOReader.


## Interface visual BookVault 3.2

A biblioteca agora usa uma camada visual própria sobre os componentes nativos do KOReader:

- cabeçalho BookVault com gato, título e subtítulo editorial;
- busca, detalhe lunar, ordenação e configurações no cabeçalho;
- abas persistentes **Todos / Lendo / Em espera / Concluídos / Não iniciados**;
- abertura direta na biblioteca, sem a tela intermediária de escolha de categoria;
- categoria ativa indicada por sublinhado monocromático;
- categorias respeitam a configuração de categorias visíveis;
- estado de seleção múltipla refletido no cabeçalho;
- menu contextual dividido em **Leitura / Organização / Capa e metadados / Arquivo / Extensões**;
- linguagem visual em preto, branco e cinzas, com linhas finas, espaçamento e tipografia simples;
- mosaico de capas continua baseado no CoverBrowser/MosaicMenu do KOReader, evitando substituir o motor de renderização por um sistema pesado.
