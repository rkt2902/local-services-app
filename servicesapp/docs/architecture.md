# LocalServices — Architecture

> Regras de organização do Projeto Principal (`local_services_app`).
> Ler antes de criar ou mover ficheiros.

## Princípios
1. Separação clara: **UI ≠ estado ≠ repositories ≠ serviços externos**.
2. Nunca chamar Supabase diretamente dentro de widgets.
3. Organização **por feature**. `core/` só para o que é partilhado por 2+ features.
4. Nomes genéricos no domínio: `client`, `worker`, `job`, `proposal`,
   `service_category`, `service_type`, `help_request`.
5. Simples, legível, evolutivo. Sem overengineering.

## Nota de nomenclatura
O domínio "prestador" chama-se `worker` no código (NÃO `provider`), para evitar
colisão com Riverpod e com `package:provider`. Na base de dados a tabela é
`worker_profiles`. Na UI mostra-se "jardineiro".

## Estrutura de pastas

```
lib/
  main.dart            # bootstrap: Supabase init + ProviderScope + runApp
  app.dart             # MaterialApp.router + theme + router
  core/
    config/            # env, SupabaseClient, constantes de config
    theme/             # ThemeData Material 3, cores, tipografia
    router/            # go_router: rotas, guards/redirect de auth
    constants/         # enums de estado, chaves, strings padrão
    utils/             # helpers genéricos (formatters, validators)
    widgets/           # widgets partilhados (PrimaryButton, AppTextField,
                       #   StatusBadge, EmptyState, etc.)
  features/
    auth/
      data/            # models + repository da feature
      application/     # Riverpod providers/controllers
      presentation/    # screens + widgets específicos da feature
    client/
    worker/
    jobs/
    proposals/
    help_requests/
    ratings/
```

## Camadas (por feature)
- **data/**: `models/` (classes imutáveis, fromJson/toJson) e `*_repository.dart`
  (única camada que fala com Supabase para esta feature).
- **application/**: providers Riverpod e controllers (estado da UI, chamam o
  repository). Sem widgets, sem Supabase direto.
- **presentation/**: screens e widgets. Só leem estado via Riverpod. Sem lógica
  de negócio nem chamadas a Supabase.

## Navegação
- go_router centralizado em `core/router/`.
- Redirect de auth: utilizador não autenticado → login; autenticado sem perfil
  → escolher tipo de conta (client/worker).

## Estado
- Riverpod. `ProviderScope` na raiz.
- Controllers expõem estados de loading / data / error explícitos.
- Toda lista deve ter estados: loading, empty e error.

## Convenções
- Ficheiros `snake_case.dart`; classes `PascalCase`.
- Um widget grande deve ser partido em widgets pequenos e reutilizáveis.
- Estados de negócio são enums (ver `database_schema.md`), nunca strings soltas.
- Correr `flutter analyze` depois de cada alteração relevante.