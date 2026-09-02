# Localization techniques

Pick by what you know, cheapest first. Every technique ends with a smaller
search space or a first appearance of the wrong value.

| Situation | Move |
|-----------|------|
| It used to work | `git bisect start; git bisect bad; git bisect good <sha>`, with the reproduction as the test (`git bisect run <cmd>` when it is a command). Ask before running the reproduction on many commits if it is slow. |
| Works with input A, fails with B | Differential run: shrink B toward A one change at a time (delta debugging by hand) until the failure flips. The last change is the trigger. |
| Works in env X, fails in Y | Diff the environments, not the code: versions (`dotnet --info`, `node -v`, lockfiles), config, env vars, locale and time zone, file system case, container vs host. |
| Wrong value at the output | Trace it backwards: log or break at each boundary (controller → service → repository → SQL) until the value is still right. The first boundary where it is wrong holds the mechanism. |
| Exception with a stack | Read the whole stack, then the *first* frame in your code, then the inputs to that frame. Inner exceptions before outer ones. |
| Intermittent | Fix the variables one by one: seed, clock, thread count (`--parallel none` / `-maxParallelThreads 1`), test order, network. See ledger.md §Flaky. |
| Only under load | Reproduce with a small concurrent driver before touching the code; shared mutable state and non-idempotent handlers are the usual mechanisms. |
| Build or startup failure | Clean build from a fresh checkout in a temp worktree (`git worktree add`) before blaming the code; stale artifacts are a mechanism too. |

Read before you instrument: the function under suspicion, its callers
(`grep` for the symbol), and the tests that already cover it. Instrument
only what reading cannot settle, and remove the instrumentation before the
fix commit.

## Per-ecosystem pointers

Quick reminders, not a tutorial; the technique above decides what to look
for.

- **.NET**: `dotnet test --filter "FullyQualifiedName~Name" --logger "console;verbosity=detailed"`; `DOTNET_` and `ASPNETCORE_ENVIRONMENT` differences; `dotnet-counters`/`dotnet-trace` for load; EF Core `LogTo` to see the SQL actually sent; `ConfigureAwait`/sync-over-async for deadlocks.
- **Node / TypeScript**: `node --inspect-brk`, `DEBUG=*` for libraries that use it, `--test-name-pattern`; unhandled promise rejections and `await` missing on a call are the common mechanisms; check `package-lock.json` for a silent minor bump.
- **Python**: `pytest -x -k name --pdb`, `PYTHONFAULTHANDLER=1`, `python -X dev`; mutable default arguments, import-time side effects, and venv vs system interpreter.
- **Go**: `go test -run Name -race -count=1`, `GODEBUG`, `pprof` for load; nil interfaces that are not nil and goroutine leaks.
- **JVM**: `-XX:+HeapDumpOnOutOfMemoryError`, `jstack` on a hang, `-Djava.security.debug`; classpath duplicates and time-zone defaults.
- **SQL**: `EXPLAIN` the actual statement (captured, not assumed), isolation level, and whether the failing row exists at all in the failing environment.
