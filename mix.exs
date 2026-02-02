defmodule FunPool.MixProject do
  use Mix.Project

  @version "1.0.0"
  @github "https://github.com/preciz/fun_pool"

  def project do
    [
      app: :fun_pool,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      package: package(),
      description: "A thin NimblePool wrapper to limit concurrency of arbitrary blocks of code",

      # Docs
      name: "FunPool",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_pool, "~> 1.1"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Barna Kovacs"],
      licenses: ["MIT"],
      links: %{"GitHub" => @github}
    ]
  end

  defp docs do
    [
      main: "FunPool",
      source_ref: "v#{@version}",
      source_url: @github,
      extras: ["README.md"]
    ]
  end
end
