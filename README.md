# BookVault 3.3.1

Biblioteca visual para KOReader, projetada para telas e-ink: monocromática, leve, minimalista e integrada às APIs nativas do KOReader.

## Interface

- Mosaico real de capas usando CoverBrowser/MosaicMenu do KOReader.
- Identidade visual BookVault em preto, branco e cinzas.
- Barra superior própria com identidade, busca, detalhe lunar, ordenação, configurações e fechamento.
- Sem botão de voltar no canto superior esquerdo.
- Grade de capas personalizável para retrato e paisagem.
- Paginação e indicadores nativos de progresso/status preservados.
- Busca visível por nome do arquivo e, quando disponível, título/autor dos metadados.
- Ordenação por título, autor, acessados recentemente, modificados recentemente, tamanho e páginas, com direção persistente.
- Ordem personalizada persistente por status e coleção.
- Categorias: Todos, Lendo, Em espera, Concluídos e Não iniciados.
- Quando integrado à barra inferior do SimpleUI por uma ação personalizada do BookVault, o plugin marca essa ação como módulo ativo enquanto a biblioteca está aberta.

## Ações por livro

- Toque abre o livro.
- Pressão longa abre o menu contextual BookVault.
- Menu contextual limpo, sem cabeçalhos/separadores textuais.
- Informações do livro com dados nativos do KOReader.
- Edição direta de título, autores, série, número da série, idioma, palavras-chave e descrição.
- Visualização e alteração da capa pela tela de informações.
- Busca de capas no Google Imagens somente quando solicitada, com prévias visuais e escolha antes da aplicação.
- Status de leitura.
- Coleções.
- Selecionar vários.
- Renomear.
- Abrir localização.
- Excluir.
- Mais ações/plugins, incluindo Copiar e Mover.

Ações destrutivas permanecem claramente separadas das ações principais sem criar blocos artificiais de categorias.

## Informações do livro

A tela BookVault usa os dados disponíveis no KOReader sempre que possível:

- nome do arquivo;
- formato;
- tamanho;
- data do arquivo;
- pasta/localização;
- capa;
- título;
- autor(es);
- série;
- número da série;
- idioma;
- palavras-chave/tags;
- descrição;
- páginas;
- progresso;
- status de leitura;
- página atual quando disponível.

Avaliação/rating e resenha/review não são exibidos.

Metadados incorretos não são alterados automaticamente. Qualquer alteração ocorre somente após ação explícita do usuário.

## Seleção múltipla

- Pressão longa entra no modo de seleção.
- Seleção/desseleção individual sem abrir livros.
- O cabeçalho muda para uma barra contextual compacta.
- Coleções, Mover, Copiar e Excluir ficam acessíveis diretamente.
- Status e ações/plugins ficam em **Mais ações**.
- Há um controle claro para sair da seleção.
- As ações atuam sobre todos os livros selecionados.
- Funciona nas categorias, coleções e resultados de busca.
- A seleção não cria trabalho em segundo plano.

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

**Limite importante:** um plugin normal do KOReader não deve interceptar globalmente toda abertura de arquivo, SimpleUI e todas as interfaces de terceiros sem hooks globais/user patches. O BookVault prioriza estabilidade e não usa monkey patches globais para tentar simular essa cobertura.

## Busca de capas

A busca no Google Imagens é totalmente sob demanda.

- Consulta usando título + autor.
- Até 6 resultados.
- Extração tolerante às estruturas de metadados do Google, sem depender somente da extensão da URL.
- Verificação do código HTTP.
- Tratamento de bloqueios/respostas inesperadas.
- Pré-visualizações pequenas para escolha.
- Somente a capa escolhida é baixada em resolução maior.
- Limites de tamanho e timeout.
- Arquivos temporários são removidos.
- A capa é aplicada pelo mecanismo nativo de capa personalizada do KOReader.
- Nenhum livro é alterado automaticamente durante o scan.
- Nenhuma busca ocorre em segundo plano.

## Operações de arquivos

Renomear, mover e copiar usam as rotinas de metadados do KOReader quando disponíveis, incluindo a atualização/migração do sidecar e da leitura. Excluir pede confirmação e limpa os metadados associados pela infraestrutura nativa antes de remover o arquivo.

## Desempenho e estabilidade

- Nenhuma busca de capa durante o scan normal.
- Rede carregada apenas quando solicitada.
- Módulos visuais pesados são carregados sob demanda.
- O mosaico continua usando componentes nativos do KOReader.
- Nenhum monkey patch global é usado.
- Ações são instaladas diretamente nos menus criados pelo próprio BookVault.
- Operações potencialmente destrutivas pedem confirmação.
- Alterações de arquivo só acontecem após ação explícita do usuário.

## AppStore

O repositório mantém a estrutura de plugin KOReader e os arquivos de metadados necessários para descoberta pela AppStore comunitária. A versão **3.3.1** está publicada no branch padrão. Esta versão também corrige a camada de ações que podia impedir o carregamento do plugin, melhora a remoção de Rating/Review e valida a aplicação da capa escolhida antes de confirmar sucesso.

Após atualizar pelo AppStore, se uma versão antiga continuar em cache, use **Refresh cache/Atualizar** e reinicie o KOReader.
