defmodule SpectreMorph.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/elchemista/spectre_morph"

  def project do
    [
      app: :spectre_morph,
      name: "Spectre Morph",
      version: @version,
      elixir: "~> 1.19",
      test_ignore_filters: [~r|^test/support/|],
      description: "Explicit, reviewable agent evolution for Elixir applications.",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      docs: [
        main: "readme",
        source_ref: "main",
        extras: ["README.md", "docs/CORE_0_4_1.md", "docs/ADAPTERS.md", "LICENSE"]
      ],
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => @source_url},
        files: ~w(lib docs examples mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
      ]
    ]
  end

  defp deps do
    [
      {:spectre, "~> 0.4.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
