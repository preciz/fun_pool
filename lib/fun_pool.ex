defmodule FunPool do
  @moduledoc """
  Limits the number of concurrent executions of anonymous functions.

  `FunPool` is a thin wrapper around `NimblePool` that allows you to easily
  throttle execution of arbitrary code blocks. This is useful for limiting
  concurrency when interacting with external resources, like APIs or databases,
  that have strict concurrency limits.

  ## Examples

      iex> child_spec = FunPool.child_spec(name: :my_pool, size: 5)
      iex> {:ok, _} = Supervisor.start_link([child_spec], strategy: :one_for_one)
      iex> FunPool.run(:my_pool, fn -> :ok end)
      :ok

  ## Timeouts

  The `run/3` function accepts a timeout (defaulting to `:infinity`). This
  timeout applies to the time spent waiting for a worker to become available
  in the pool. It does not include the execution time of the function itself.
  """

  @behaviour NimblePool

  @doc """
  Returns a child specification for starting a `FunPool` under a supervisor.

  ## Options

    * `:name` (required) - the name of the pool.
    * `:size` (optional) - the maximum number of concurrent executions. Defaults to `5`.
  """
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    size = Keyword.get(opts, :size, 5)

    %{
      id: name,
      start: {NimblePool, :start_link, [[worker: {__MODULE__, []}, name: name, pool_size: size]]}
    }
  end

  @doc """
  Runs the given function in the specified pool.

  The function is executed when a worker becomes available in the pool.
  If no worker is available within the `timeout`, the calling process will exit.

  ## Parameters

    * `pool` - the name (atom, pid, or via-tuple) of the pool to run the function in.
    * `function` - an anonymous function with zero arity.
    * `timeout` - how long to wait for a worker to become available (default `:infinity`).

  ## Returns

  The result of the anonymous function.
  """
  @spec run(any(), (-> any()), timeout()) :: any()
  def run(pool, function, timeout \\ :infinity) when is_function(function, 0) do
    NimblePool.checkout!(
      pool,
      :checkout,
      fn _worker, worker_state ->
        {function.(), worker_state}
      end,
      timeout
    )
  end

  @impl NimblePool
  def init_worker([]) do
    {:ok, [], []}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, [], []) do
    {:ok, [], [], []}
  end
end
