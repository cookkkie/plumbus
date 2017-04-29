defmodule Plumbus do
  @moduledoc """
  A set of useful functions for elixir
  """

  @doc """
  Flushes the current process mailbox. Similar to IEx's flush/0
  """
  def flush, do: flush([])
  defp flush(messages) do
    receive do
      message -> flush([message | messages])
    after
      0 -> messages
    end
  end

  @doc """
  Casts every key of a map into an atom, recursively!

  ## Examples

      iex> atoms_map(%{"plumbus" => 4242, "factory" => %{"plumbus" => 4242}})
      %{plumbus: 4242, factory: %{plumbus: 4242}}
  """
  def atoms_map(%{} = map) do
    for {key, value} <- map do
      key =
        case is_bitstring(key) do
          true -> String.to_atom(key)
          false -> key
        end

      value =
        case is_map(value)  do
          true -> atoms_map(value)
          false -> 
            case is_list(value) do
              true ->
                Enum.map(value, fn elem ->
                  atoms_map(elem)
                end)
              false -> value
            end
        end

      {key, value}
    end |> Enum.into(%{})
  end
  def atoms_map(not_a_map), do: not_a_map
  
  @doc """
  Gets the value of an environment variable.

  ## Examples

      iex> get_env("PLUMBUSSES", :dingle_bop, :atom, :list)
      [:plumbus_1, :plumbus_2, :plumbus_3]

      iex> get_env("PLUMBUS_COUNT", 1, :integer)
      52

      iex> get_env("IS_PLUMBUS", false, :boolean)
      true
  """
  def get_env(env_name, default \\ nil, cast_to \\ nil, list \\ false) do
    env = System.get_env(env_name)
    env = 
      if list do
        String.split(env, ",")
      else
        env
      end

    process_env(env, default, cast_to)
  end

  defp process_env([], _, _), do: []
  defp process_env([h|t], default, cast_to), do: [process_env(h, default, cast_to)|process_env(t, default, cast_to)]
  defp process_env(env, default, cast_to) do
    case env do
      nil -> default
      env -> 
        case cast_to do
          nil -> env
          :string -> env
          :atom -> String.to_atom(env)
          :integer -> String.to_integer(env)
          :boolean -> !!env
        end
    end
  end
end
