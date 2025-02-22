defmodule Mix.Tasks.Phx.Gen.Html do
  @shortdoc "Generates controller, views, and context for an HTML resource"

  @moduledoc """
  Generates controller, views, and context for an HTML resource.

      mix phx.gen.html Accounts User users name:string age:integer

  The first argument is the context module followed by the schema module
  and its plural name (used as the schema table name).

  The context is an Elixir module that serves as an API boundary for
  the given resource. A context often holds many related resources.
  Therefore, if the context already exists, it will be augmented with
  functions for the given resource.

  > Note: A resource may also be split
  > over distinct contexts (such as `Accounts.User` and `Payments.User`).

  The schema is responsible for mapping the database fields into an
  Elixir struct. It is followed by an optional list of attributes,
  with their respective names and types. See `mix phx.gen.schema`
  for more information on attributes.

  Overall, this generator will add the following files to `lib/`:

    * a context module in `lib/app/accounts.ex` for the accounts API
    * a schema in `lib/app/accounts/user.ex`, with an `users` table
    * a view in `lib/app_web/views/user_view.ex`
    * a controller in `lib/app_web/controllers/user_controller.ex`
    * default CRUD templates in `lib/app_web/templates/user`

  ## The context app

  A migration file for the repository and test files for the context and
  controller features will also be generated.

  The location of the web files (controllers, views, templates, etc) in an
  umbrella application will vary based on the `:context_app` config located
  in your applications `:generators` configuration. When set, the Phoenix
  generators will generate web files directly in your lib and test folders
  since the application is assumed to be isolated to web specific functionality.
  If `:context_app` is not set, the generators will place web related lib
  and test files in a `web/` directory since the application is assumed
  to be handling both web and domain specific functionality.
  Example configuration:

      config :my_app_web, :generators, context_app: :my_app

  Alternatively, the `--context-app` option may be supplied to the generator:

      mix phx.gen.html Sales User users --context-app warehouse

  ## Web namespace

  By default, the controller and view will be namespaced by the schema name.
  You can customize the web module namespace by passing the `--web` flag with a
  module name, for example:

      mix phx.gen.html Sales User users --web Sales

  Which would generate a `lib/app_web/controllers/sales/user_controller.ex` and
  `lib/app_web/views/sales/user_view.ex`.

  ## Customizing the context, schema, tables and migrations

  In some cases, you may wish to bootstrap HTML templates, controllers,
  and controller tests, but leave internal implementation of the context
  or schema to yourself. You can use the `--no-context` and `--no-schema`
  flags for file generation control.

  You can also change the table name or configure the migrations to
  use binary ids for primary keys, see `mix phx.gen.schema` for more
  information.
  """
  use Mix.Task

  alias Mix.Phoenix.{Context, Schema}
  alias Mix.Tasks.Phx.Gen

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise "mix phx.gen.html must be invoked from within your *_web application root directory"
    end

    {context, schema} = Gen.Context.build(args)
    Gen.Context.prompt_for_code_injection(context)

    binding = [context: context, schema: schema, inputs: inputs(schema)]
    paths = Mix.Phoenix.generator_paths()

    prompt_for_conflicts(context)

    context
    |> copy_new_files(paths, binding)
    |> print_shell_instructions()
  end

  defp prompt_for_conflicts(context) do
    context
    |> files_to_be_generated()
    |> Kernel.++(context_files(context))
    |> Mix.Phoenix.prompt_for_conflicts()
  end
  defp context_files(%Context{generate?: true} = context) do
    Gen.Context.files_to_be_generated(context)
  end
  defp context_files(%Context{generate?: false}) do
    []
  end

  @doc false
  def files_to_be_generated(%Context{schema: schema, context_app: context_app}) do
    web_prefix = Mix.Phoenix.web_path(context_app)
    test_prefix = Mix.Phoenix.web_test_path(context_app)
    web_path = to_string(schema.web_path)

    [
      {:eex, "controller.ex",       Path.join([web_prefix, "controllers", web_path, "#{schema.singular}_controller.ex"])},
      {:eex, "edit.html.heex",      Path.join([web_prefix, "templates", web_path, schema.singular, "edit.html.heex"])},
      {:eex, "index.html.heex",     Path.join([web_prefix, "templates", web_path, schema.singular, "index.html.heex"])},
      {:eex, "new.html.heex",       Path.join([web_prefix, "templates", web_path, schema.singular, "new.html.heex"])},
      {:eex, "show.html.heex",      Path.join([web_prefix, "templates", web_path, schema.singular, "show.html.heex"])},
      {:eex, "view.ex",             Path.join([web_prefix, "views", web_path, "#{schema.singular}_view.ex"])},
      {:eex, "controller_test.exs", Path.join([test_prefix, "controllers", web_path, "#{schema.singular}_controller_test.exs"])},
    ]
  end

  @doc false
  def copy_new_files(%Context{} = context, paths, binding) do
    files = files_to_be_generated(context)
    Mix.Phoenix.copy_from(paths, "priv/templates/phx.gen.html", binding, files)
    if context.generate?, do: Gen.Context.copy_new_files(context, paths, binding)
    context
  end

  @doc false
  def print_shell_instructions(%Context{schema: schema, context_app: ctx_app} = context) do
    if schema.web_namespace do
      Mix.shell().info """

      Add the resource to your #{schema.web_namespace} :browser scope in #{Mix.Phoenix.web_path(ctx_app)}/router.ex:

          scope "/#{schema.web_path}", #{inspect Module.concat(context.web_module, schema.web_namespace)}, as: :#{schema.web_path} do
            pipe_through :browser
            ...
            resources "/#{schema.plural}", #{inspect schema.alias}Controller
          end
      """
    else
      Mix.shell().info """

      Add the resource to your browser scope in #{Mix.Phoenix.web_path(ctx_app)}/router.ex:

          resources "/#{schema.plural}", #{inspect schema.alias}Controller
      """
    end
    if context.generate?, do: Gen.Context.print_shell_instructions(context)
  end

  @doc false
  def inputs(%Schema{} = schema) do
    Enum.map(schema.attrs, fn
      {_, {:references, _}} ->
        nil
      {key, :integer} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="number" label="#{label(key)}" />)
      {key, :float} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="number" label="#{label(key)}" step="any" />)
      {key, :decimal} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="number" label="#{label(key)}" step="any" />)
      {key, :boolean} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="checkbox" label="#{label(key)}" />)
      {key, :text} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="text" label="#{label(key)}" />)
      {key, :date} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="date" label="#{label(key)}" />)
      {key, :time} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="time" label="#{label(key)}" />)
      {key, :utc_datetime} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="datetime-local" label="#{label(key)}" />)
      {key, :naive_datetime} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="datetime-local" label="#{label(key)}" />)
      {key, {:array, :integer}} ->
        ~s(<.input field={{f, #{inspect(key)}}} type="datetime-local" label="#{label(key)}" />)
      {key, {:array, _}} ->
        ~s"""
        <.input field={{f, #{inspect(key)}}} type="select" multiple label="#{label(key)}">
          <:option value="option1">Option 1</:option>
          <:option value="option2">Option 2</:option>
        </.input>
        """
      {key, {:enum, _}}  ->
        ~s"""
        <.input field={{f, #{inspect(key)}}} type="select" label="#{label(key)}">
          <:option>Choose a value</:option>
          <%= for value <- Ecto.Enum.values(#{inspect(schema.module)}, #{inspect(key)}) do %>
            <:option value={value}><%= value %></:option>
          <% end %>
        </.input>
        """
      {key, _}  ->
        ~s(<.input field={{f, #{inspect(key)}}} type="text" label="#{label(key)}" />)
    end)
  end

  defp label(key), do: to_string(key)
end
