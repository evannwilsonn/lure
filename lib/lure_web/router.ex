defmodule LureWeb.Router do
  use LureWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LureWeb.Layouts, :root}
    plug :protect_from_forgery
    # Spaces shows the app inside a frame on huggingface.co, so that site may frame it.
    plug :put_secure_browser_headers, %{
      "content-security-policy" => "frame-ancestors 'self' https://huggingface.co"
    }

    plug :allow_framing
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LureWeb do
    pipe_through :browser

    live "/", CheckLive
  end

  defp allow_framing(conn, _opts), do: Plug.Conn.delete_resp_header(conn, "x-frame-options")

  # Other scopes may use custom stacks.
  # scope "/api", LureWeb do
  #   pipe_through :api
  # end
end
