{{/* Read-only startup barrier shared by every serving role, including external migrations. */}}
{{- define "codex-pooler.migrationReadiness" -}}
- name: wait-for-schema
  image: {{ include "codex-pooler.image" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  command: ["timeout", {{ printf "%ds" (int .Values.migrations.activeDeadlineSeconds) | quote }}, "/app/bin/codex_pooler", "eval"]
  args:
    - |
      Application.load(:codex_pooler)
      {:ok, :ok, _} = Ecto.Migrator.with_repo(CodexPooler.Repo, fn repo ->
        entries = case File.ls(Ecto.Migrator.migrations_path(repo)) do
          {:ok, entries} -> entries
          {:error, _} -> raise("schema_wait_migration_directory_unreadable")
        end
        versions =
          entries
          |> Enum.reject(&(&1 == ".formatter.exs"))
          |> Enum.filter(&String.ends_with?(&1, ".exs"))
          |> Enum.map(fn entry ->
            case Regex.run(~r/\A(\d+)_.+\.exs\z/, entry, capture: :all_but_first) do
              [version] -> String.to_integer(version)
              _ -> raise("schema_wait_migration_files_malformed")
            end
          end)
        if versions == [], do: raise("schema_wait_migration_files_missing")
        if Enum.uniq(versions) != versions, do: raise("schema_wait_migration_files_malformed")
        deadline = System.monotonic_time(:millisecond) + {{ mul (sub (int .Values.migrations.activeDeadlineSeconds) 10) 1000 }}
        remaining = fn ->
          left = deadline - System.monotonic_time(:millisecond)
          if left <= 0, do: raise("schema_wait_timeout")
          left
        end
        query = fn statement, params ->
          Ecto.Adapters.SQL.query(repo, statement, params, timeout: min(1_000, remaining.()))
        end
        ready = fn ->
          with {:ok, %{rows: [[table]]}} when not is_nil(table) <- query.("SELECT to_regclass('schema_migrations')", []),
               {:ok, %{rows: [[count]]}} <- query.("SELECT count(*) FROM schema_migrations WHERE version = ANY($1)", [versions]) do
            count == length(versions)
          else
            _ -> false
          end
        end
        await = fn await, announced ->
          remaining.()
          complete = ready.()
          left = remaining.()
          if complete do
            IO.puts("schema_wait=ready")
            :ok
          else
            if not announced, do: IO.puts("schema_wait=pending")
            Process.sleep(min(1_000, left))
            await.(await, true)
          end
        end
        await.(await, false)
      end)
  env:
    - name: OBAN_MODE
      value: web
    {{- include "codex-pooler.env" . | nindent 4 }}
  resources:
    {{- toYaml .Values.migrations.resources | nindent 4 }}
{{- end -}}
