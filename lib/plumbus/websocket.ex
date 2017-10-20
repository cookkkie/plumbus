defmodule Plumbus.Websocket do
  @behaviour :websocket_client

  require Logger

  def start(uri, opts \\ []) do
    :crypto.start()
    :ssl.start()
    :websocket_client.start(uri, __MODULE__, {self(), opts})
  end

  def init({parent, opts}) do
    format = Keyword.get(opts, :format, :etf)
    zlib   =
      if Keyword.get(opts, :zlib, false) do
        z = :zlib.open()
        :zlib.inflateInit(z)
        z
      else
        nil
      end

    state = %{
      parent: parent,
      format: format,
      buffer: <<>>,
      zlib:   zlib
    }

    {:once, state}
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
    if state.zlib do
      :zlib.close(state.zlib)
    end
  end

  def websocket_handle({dtype, data}, _socket, %{zlib: nil}=state) do
    handle_data(data, state)
  end

  def websocket_handle({_dtype, packet}, _socket, %{zlib: z, buffer: buffer}=state) do
    buffer     = buffer <> packet
    last_bytes = packet |> :binary.bin_to_list() |> Enum.take(-4)

    {buffer, data} = 
      if last_bytes == [0, 0, 0xFF, 0xFF] do
        uncompressed =
          z
          |> :zlib.inflate(buffer)
          |> :erlang.iolist_to_binary()
        {<<>>, uncompressed}
      else
        {buffer, nil}
      end
    
    if data, do: handle_data(data, state)

    {:ok, %{state | buffer: buffer}}
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
