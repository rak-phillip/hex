defmodule Hex.Mixfile do
  use Mix.Project

  def project do
    [app: :hex,
     version: "0.12.0-dev",
     elixir: "~> 1.0",
     aliases: aliases,
     deps: deps,
     elixirc_options: elixirc_options(Mix.env),
     elixirc_paths: elixirc_paths(Mix.env)]
  end

  def application do
    [applications: applications(Mix.env),
     mod: {Hex, []}]
  end

  defp applications(:test), do: [:ssl, :inets, :logger]
  defp applications(_),     do: [:ssl, :inets]

  # Can't use hex dependencies because the elixir compiler loads dependencies
  # and calls the dependency SCM. This would cause us to crash if the SCM was
  # Hex because we have to unload Hex before compiling it.
  defp deps do
    [{:bypass, github: "ericmj/bypass", branch: "emj-multi-bypass", only: :test},
     {:plug,   github: "elixir-lang/plug", tag: "v1.1.2", only: :test, override: true},
     {:cowboy, github: "ninenines/cowboy", tag: "1.0.4", only: :test, override: true},
     {:cowlib, github: "ninenines/cowlib", tag: "1.0.2", only: :test, override: true},
     {:ranch,  github: "ninenines/ranch", tag: "1.2.1", only: :test, override: true}]
  end

  defp elixirc_options(:prod), do: [debug_info: false]
  defp elixirc_options(_),     do: []

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  defp aliases do
    ["compile.elixir": [&unload_hex/1, "compile.elixir"],
     run: [&unload_hex/1, "run"],
     install: ["archive.build -o hex.ez", "archive.install hex.ez --force"],
     certdata: [&certdata/1]]
  end

  defp unload_hex(_) do
    Application.stop(:hex)
    paths = Path.join(archives_path(), "hex*.ez") |> Path.wildcard

    Enum.each(paths, fn archive ->
      ebin = archive_ebin(archive)
      Code.delete_path(ebin)

      {:ok, files} = :erl_prim_loader.list_dir(to_char_list(ebin))

      Enum.each(files, fn file ->
        file = List.to_string(file)
        size = byte_size(file) - byte_size(".beam")

        case file do
          <<name :: binary-size(size), ".beam">> ->
            module = String.to_atom(name)
            :code.delete(module)
            :code.purge(module)
          _ ->
            :ok
        end
      end)
    end)
  end

  @mk_ca_bundle_url "https://raw.githubusercontent.com/bagder/curl/master/lib/mk-ca-bundle.pl"
  @mk_ca_bundle_cmd "mk-ca-bundle.pl"
  @ca_bundle        "ca-bundle.crt"
  @ca_bundle_target Path.join("lib/hex/api", @ca_bundle)

  defp certdata(_) do
    cmd("wget", [@mk_ca_bundle_url])
    File.chmod!(@mk_ca_bundle_cmd, 0o755)

    cmd(Path.expand(@mk_ca_bundle_cmd), ["-u"])

    File.cp!(@ca_bundle, @ca_bundle_target)
    File.rm!(@ca_bundle)
    File.rm!(@mk_ca_bundle_cmd)
  end

  defp cmd(cmd, args) do
    {_, result} = System.cmd(cmd, args, into: IO.stream(:stdio, :line),
                             stderr_to_stdout: true)

    if result != 0 do
      raise "Non-zero result (#{result}) from: #{cmd} #{Enum.map_join(args, " ", &inspect/1)}"
    end
  end

  defp archives_path do
    if function_exported?(Mix.Local, :path_for, 1),
      do: Mix.Local.path_for(:archive),
    else: Mix.Local.archives_path
  end

  defp archive_ebin(archive) do
    if function_exported?(Mix.Local, :archive_ebin, 1),
      do: Mix.Local.archive_ebin(archive),
    else: Mix.Archive.ebin(archive)
  end
end
