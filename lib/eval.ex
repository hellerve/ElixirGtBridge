defmodule Eval do
  use GenServer
  use TypedStruct

  typedstruct do
    field(:bindings, Code.binding())
    field(:port, non_neg_integer(), default: nil)
  end

  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(init_args) do
    port = Keyword.get(init_args, :port, nil)
    default_bindings = if port, do: [port: port], else: []
    {:ok, %__MODULE__{bindings: default_bindings, port: port}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec eval(GenServer.server(), String.t(), String.t() | nil) :: any()
  def eval(pid, code, command_id) do
    GenServer.call(pid, {:eval, code, command_id})
  end

  @doc """
  Remove an object from the registry.
  Called by GT when a proxy object is garbage collected.
  """
  @spec remove(non_neg_integer()) :: :ok
  def remove(id) do
    GtBridge.ObjectRegistry.remove(id)
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  # TODO garbage collect old values in the environment after a while
  @impl true
  def handle_call({:eval, string, command_id}, _from, state = %__MODULE__{}) do
    {term, new_bindings} =
      string
      |> String.replace("\r", "\n")
      |> Code.eval_string(state.bindings ++ [command_id: command_id])

    # Remove duplicated keys and ports
    unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

    {:reply, term, %__MODULE__{state | bindings: unique_keys}}
  end

  @spec notify(term(), String.t(), pos_integer()) :: term()
  def notify(obj, id, port) do
    require Logger
    Logger.info("Notify called: obj=#{inspect(obj)}, id=#{id}, port=#{port}")

    # Register the object and get a unique ID (nil for primitives)
    exid = GtBridge.ObjectRegistry.register(obj)

    # If it's a primitive (exid is nil), send it directly without wrapping
    value_json_string = if exid == nil do
      # Primitive - send as-is
      {:ok, json} = Jason.encode(obj)
      json
    else
      # Complex object - wrap with metadata (lazy loading, no value)
      # Get class info for the object
      exclass = cond do
        is_struct(obj) ->
          # Get the module name from __struct__ and clean it up
          obj.__struct__
          |> to_string()
          |> String.replace_prefix("Elixir.", "")

        is_list(obj) ->
          "List"

        is_map(obj) ->
          "Map"

        is_tuple(obj) ->
          "Tuple"

        true ->
          case IEx.Info.info(obj) do
            info when is_list(info) ->
              case Enum.at(info, 1) do
                {_, class} -> class
                _ -> "Unknown"
              end
            _ -> "Unknown"
          end
      end

      # The value object with metadata (no value field for lazy loading)
      value_object = %{
        exclass: exclass,
        exid: exid
      }

      {:ok, json} = Jason.encode(value_object)
      json
    end

    data = %{
      type: "EVAL",
      id: id,
      value: value_json_string,
      __sync: "_"
    }

    url = "http://localhost:" <> to_string(port) <> "/EVAL"
    Logger.info("POSTing to #{url} with data: #{inspect(data)}")

    response = Req.post!(url, json: data)
    Logger.info("POST response: #{inspect(response)}")

    obj
  end

end
