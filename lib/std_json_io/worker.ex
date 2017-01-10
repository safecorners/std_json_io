defmodule StdJsonIo.Worker do
  use GenServer
  alias Porcelain.Process, as: Proc
  alias Porcelain.Result
  alias StdJsonIo.JsonUtils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts[:script], opts)
  end

  def init(script) do
    :erlang.process_flag(:trap_exit, true)
    {:ok, %{js_proc: start_io_server(script)}}
  end

  def handle_call({:json, blob}, _from, state) do
    payload =
      case Poison.encode(blob) do
        nil -> {:error, :json_error}
        {:error, reason} -> {:error, reason}
        {:ok, json} ->
          Proc.send_input(state.js_proc, json)
          wait_for_response([])
      end
    {:reply, payload, state}
  end

  def handle_call(:stop, _from, state), do: {:stop, :normal, :ok, state}

  # The js server has stopped
  def handle_info({_js_pid, :result, %Result{err: _, status: _status}}, state) do
    {:stop, :normal, state}
  end

  def terminate(_reason, %{js_proc: server}) do
    Proc.signal(server, :kill)
    Proc.stop(server)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_io_server(script) do
    Porcelain.spawn_shell(script, in: :receive, out: {:send, self()})
  end


  defp wait_for_response(buffer) do
    receive do
      {_js_pid, :data, :out, msg} ->
        if JsonUtils.complete_json?(msg, buffer) do
          output = JsonUtils.package_complete_json(msg, buffer)
          {:ok, output}
        else
          temp = JsonUtils.wrap_incomplete_json(msg, buffer)
          wait_for_response(temp)
        end
      response ->
        {:error, response}
    end
  end
end
