defmodule Plumbus.Websocket do
  @behaviour :websocket_client

  require Logger

  def start(uri, opts \\ []) do
    format = Keyword.get(opts, :format, :etf)
    zlib_stream = Keyword.get(opts, :zlib_stream, false)
    :crypto.start()
    :ssl.start()
    :websocket_client.start(uri, __MODULE__, [self(), format, zlib_stream])
  end

  def init([parent, format, zlib_stream]) do
    zlib_stream =
      if zlib_stream do
        z = :zlib.open()
        :zlib.inflateInit(z)
        {<<>>, z}
      else
        nil
      end
    {:once, %{parent: parent, format: format, zlib_stream: zlib_stream}}
  end

  def onconnect(_, state) do
    state |> forward_frame(:connected)
    {:ok, state}
  end

  def ondisconnect(reason, state) do
    state |> forward_frame({:close, reason})
    {:close, reason, state}
  end

  def send(ws_pid, frame) do
    :websocket_client.cast(ws_pid, frame)
  end

  def send_binary(ws_pid, frame) do
    :websocket_client.cast(ws_pid, {:binary, frame})
  end

  def close(ws_pid, code) do
    Kernel.send(ws_pid, {:close, code})
  end

  def websocket_info({:close, code}, _conn, state) do
    {:close, code |> to_string(), state}
  end

  def websocket_terminate(_reason, _conn, state) do
    if state.zlib_stream do
      {_buffer, z} = state.zlib_stream
      :zlib.close(z)
    end
    :ok
  end

  def websocket_handle({_dtype, data}, _socket, %{zlib_stream: {buffer, z}}=state) do
    size = byte_size(data)
    buffer = buffer <> data
    buffer_head_size = byte_size(data) - 4
    
    {buffer, data} =
      case buffer do
        <<_::bytes-size(buffer_head_size), 0, 0, 255, 255>> ->
          uncompressed =
            :zlib.inflate(z, buffer)
            |> :erlang.iolist_to_binary()
          {<<>>, uncompressed}
        data ->
          {buffer, nil}
      end

    if data, do: handle_data(data, state)

    {:ok, %{state | zlib_stream: {buffer, z}}}
  end

  def websocket_handle({dtype, data}, _socket, %{zlib_stream: nil}=state) do
    handle_data(data, state)
  end

  def websocket_handle(data, _socket, state) do
    forward_frame(state, data)
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
