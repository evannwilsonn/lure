defmodule Lure.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The trained scam model, loaded before anything can ask for a verdict.
    Lure.Detector.load!()

    children = [
      LureWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:lure, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Lure.PubSub},
      # The MiniLM embedding model behind a batching server, so concurrent checks share one
      # compiled model.
      {Nx.Serving,
       serving: Lure.Embedder.serving(batch_size: 4), name: Lure.Embeddings, batch_timeout: 20},
      # Start a worker by calling: Lure.Worker.start_link(arg)
      # {Lure.Worker, arg},
      # Start to serve requests, typically the last entry
      LureWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lure.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LureWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
