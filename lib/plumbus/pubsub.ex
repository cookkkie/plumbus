defmodule Plumbus.PubSub do

  def init, do: :pg2.start()

  def subscribe(channel, pid) do
    :pg2.create(channel)
    :pg2.join(channel, pid)
  end

  def publish(channel, message) do
    :pg2.create(channel)
    for pid <- :pg2.get_members(channel) do
      GenServer.cast(pid, message)
    end
  end
end
