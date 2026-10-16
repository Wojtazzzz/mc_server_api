defmodule McServerApiWeb.Router do
  use McServerApiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {McServerApiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: McServerApiWeb.ApiSpec
  end

  scope "/", McServerApiWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", McServerApiWeb do
    pipe_through :api

    get "/status/:address", StatusController, :show
  end

  # OpenAPI spec and Swagger UI; plugs from OpenApiSpex, so outside the McServerApiWeb alias.
  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api" do
    pipe_through :browser

    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:mc_server_api, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
