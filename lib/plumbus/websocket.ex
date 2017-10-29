defmodule Plumbus.Websocket do
  use WebSockex

  def start(uri, opts \\ []) do
    parent      = Keyword.get(opts, :parent, self())
    format      = Keyword.get(opts, :format, :etf)
    zlib_stream = Keyword.get(opts, :zlib_stream, false)

    state = %{parent: parent, format: format, zlib_stream: zlib_stream}

    WebSockex.start(uri, __MODULE__, state, async: true)
  end

  def handle_connect(_conn, state) do
    zlib_stream =
      if state.zlib_stream do
        z = :zlib.open()
        :zlib.inflateInit(z)
        {<<>>, z}
      else
        nil
      end

    state |> forward_frame(:connected)
    {:ok, %{state | zlib_stream: zlib_stream}}
  end

  def handle_disconnect(%{reason: reason}, state) do
    state |> forward_frame({:close, reason})
    {:ok, state}
  end

  def send(ws_pid, frame) do
    WebSockex.send_frame(ws_pid, frame)
  end

  def send_binary(ws_pid, bin) do
    WebSockex.send_frame(ws_pid, {:binary, bin})
  end

  def close(ws_pid, code) when is_binary(code) do
    close(ws_pid, String.to_integer(code))
  end

  def close(ws_pid, code) when is_number(code) do
    Kernel.send(ws_pid, {:close, code})
  end

  def handle_info({:close, code}, state) do
    {:close, {code, ""}, state}
  end

  def terminate(_reason, state) do
    if state.zlib_stream do
      {_, z} = state.zlib_stream
      :zlib.close(z)
    end
    :ok
  end

  def handle_frame({_dtype, data}, %{zlib_stream: {buffer, z}}=state) do
    buffer = buffer <> data
    buffer_head_size = byte_size(data) - 4
    
    {buffer, data} =
      case buffer do
        <<_::bytes-size(buffer_head_size), 0, 0, 255, 255>> ->
          uncompressed =
            :zlib.inflate(z, buffer)
            |> :erlang.iolist_to_binary()
          {<<>>, uncompressed}
        _data ->
          {buffer, nil}
      end

    if data, do: handle_data(data, state)

    {:ok, %{state | zlib_stream: {buffer, z}}}
  end

  def handle_frame({_dtype, data}, %{zlib_stream: nil}=state) do
    handle_data(data, state)
  end

  defp handle_data(data, %{format: nil}=state) do
    forward_frame(state, {:data, data})
    {:ok, state}
  end

  defp handle_data(data, %{format: format}=state) do
    payload = decode(format, data)
    forward_frame(state, {:data, payload})
    {:ok, state}
  end

  defp forward_frame(%{parent: parent}, frame) do
    Kernel.send(parent, {:websocket, self(), frame})
  end

  defp decode(:json, data), do: Poison.decode!(data)

  defp decode(:etf, data), do: :erlang.binary_to_term(data)
end

