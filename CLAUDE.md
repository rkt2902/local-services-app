# ProJardim (LocalServices)

Marketplace de serviços locais (Flutter + Supabase), lançado focado em jardinagem mas
com código e schema genéricos. Dois papéis: cliente (cria pedidos, aceita propostas,
avalia) e worker/"jardineiro" na UI (propõe, executa, pede ajudantes). Projeto real
em `servicesapp/`; `ui_playground/` e `doc.txt` são material de referência à parte.

## Antes de cada tarefa

Lê sempre `servicesapp/docs/ARCHITECTURE.md` primeiro (como a app funciona, extraído
do código). Depois, só os outros documentos em `servicesapp/docs/` que forem
relevantes para a tarefa em concreto, não todos de cada vez:

- `STATUS.md` — o que funciona, o que não, gaps conhecidos, sem spin.
- `database_schema.md` / `state_machine.md` — schema e transições de estado (confirma
  contra `ARCHITECTURE.md` e os ficheiros de `supabase/migrations/`, que são a fonte
  de verdade mais recente).
- `decisions_log.md` — histórico de decisões técnicas, por data.
- `improvements.md` — dívida técnica e ideias futuras conhecidas.
- `motion_spec.md` — especificação de movimento.
- `SETUP.md` — configuração que só o Henrique faz (Netlify, Supabase, email, Firebase,
  domínio), por ordem.

## Regras que nunca se quebram

- **Nunca aplicar migrations.** Só criar o ficheiro `.sql` em `supabase/migrations/`.
  Dizer sempre, no relatório, se a migration foi só criada ou se foi (ou deve ser)
  aplicada manualmente via SQL Editor.
- **RPCs nunca recebem `worker_id`/`client_id`/`user_id` vindos da app.** Identidade
  é sempre `auth.uid()` dentro da função. Isto já causou 3 vulnerabilidades reais
  (migration 0032) — nunca reintroduzir a classe.
- **`DROP FUNCTION` explícito antes de recriar** quando o `RETURNS TABLE` de uma RPC
  muda de forma. `CREATE OR REPLACE` não é suficiente nesse caso.
- **Regra T4**: numa ação com navegação, a ordem é sempre navegar (go/pop) → SnackBar
  → `ref.invalidate(...)`. Invalidar antes de navegar pode rebentar o ecrã atual.
- **"worker" no código, nunca "provider"** (colisão com Riverpod). Na UI é sempre
  "Jardineiro".
- **Contacto só por WhatsApp.** Nunca chat/email dentro da app.
- **Só tokens do design system**: `AppColors`, `AppSpacing`, `AppRadius`, `textTheme`.
  Nunca `Color(0xFF...)` nem tamanhos soltos fora de `core/theme/`.
- **Motion obrigatório em ecrãs novos** — ver `servicesapp/docs/motion_spec.md` e os
  widgets em `core/widgets/app_motion.dart`.
- **Ecrãs de sub-fluxo ficam fora dos `ShellRoute`**, com `SafeArea` própria — só os
  9 ecrãs de topo (dentro de `ClientShell`/`WorkerShell`) mostram a bottom nav.
- **`doc.txt`** (raiz do workspace) é referência para adaptar, nunca para copiar
  literalmente, e não se apaga.
- **Serviços e categorias vêm sempre de `serviceTypesProvider`**, nunca hardcoded —
  a base de dados não sabe que isto é jardinagem.

## Comandos úteis

```bash
cd servicesapp
flutter run                 # correr a app (ver .vscode/launch.json para --dart-define)
flutter analyze              # obrigatório depois de qualquer alteração relevante
flutter test                  # só 1 smoke test hoje (test/widget_test.dart)
```

## Formato do relatório no fim de cada tarefa

1. Ficheiros alterados.
2. Migrations criadas (nome do ficheiro) e se foram ou não aplicadas.
3. Riscos.
4. O que testar.
5. Resultado completo de `flutter analyze`.

## Idioma dos relatórios

Português de Portugal, sem travessões.
