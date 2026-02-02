# FunPool

[![test](https://github.com/preciz/fun_pool/actions/workflows/test.yml/badge.svg)](https://github.com/preciz/fun_pool/actions/workflows/test.yml)

Limits the number of concurrent executions of anonymous functions.

`FunPool` is a thin, easy-to-use wrapper around [NimblePool](https://github.com/dashbitco/nimble_pool). It is designed for scenarios where you need to limit concurrency for arbitrary blocks of code without the overhead of defining custom worker modules.

## Installation

Add `fun_pool` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fun_pool, "~> 1.0"}
  ]
end
```

## Usage

### 1. Start the pool

Start the pool in your supervision tree. You must provide a `:name` and can optionally provide a `:size` (defaults to 5).

```elixir
children = [
  FunPool.child_spec(name: MyPool, size: 10)
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### 2. Run functions in the pool

Pass the pool name and an anonymous function to `FunPool.run/3`.

```elixir
FunPool.run(MyPool, fn ->
  # This code is execution-limited by the pool size
  :ok = do_some_heavy_lifting()
end)
```

### 3. Handling Timeouts

By default, `run/3` will wait indefinitely for a worker. You can specify a timeout in milliseconds:

```elixir
try do
  FunPool.run(MyPool, fn -> :ok end, 5000)
catch
  :exit, {:timeout, _} ->
    IO.puts("Pool was too busy!")
end
```

## How it works

`FunPool` implements the `NimblePool` behaviour. Each "worker" in the pool is essentially a placeholder that represents a concurrency slot. When you call `run/3`, it checks out a worker, executes your function in the calling process, and then checks the worker back in.

This approach is extremely lightweight as it doesn't involve moving large amounts of data between processes; the function runs in the process that calls `run/3`.

## License

MIT License - see the [LICENSE](LICENSE) file for details.
