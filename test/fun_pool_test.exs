defmodule FunPoolTest do
  use ExUnit.Case
  doctest FunPool

  setup do
    name = Module.concat(__MODULE__, "Pool_#{System.unique_integer([:positive])}")

    start_supervised!(FunPool.child_spec(name: name, size: 1))

    %{pool: name}
  end

  test "runs a function in the pool", %{pool: pool} do
    assert FunPool.run(pool, fn -> :ok end) == :ok
  end

  test "serializes execution when pool is small (size 1)", %{pool: pool} do
    parent = self()

    spawn_link(fn ->
      FunPool.run(pool, fn ->
        send(parent, :in_pool)
        Process.sleep(200)
      end)
    end)

    assert_receive :in_pool

    t2 =
      Task.async(fn ->
        FunPool.run(pool, fn -> :done end)
      end)

    case Task.yield(t2, 50) do
      nil -> :ok
      _ -> flunk("Task 2 should have been blocked")
    end

    assert Task.await(t2, 500) == :done
  end

  test "throws a fit (timeout) when it's too crowded", %{pool: pool} do
    parent = self()

    spawn_link(fn ->
      FunPool.run(pool, fn ->
        send(parent, :occupied)
        Process.sleep(200)
      end)
    end)

    assert_receive :occupied

    assert catch_exit(FunPool.run(pool, fn -> :too_late end, 50)) ==
             {:timeout, {NimblePool, :checkout, [pool]}}
  end

  test "function crash doesn't break the pool", %{pool: pool} do
    assert_raise RuntimeError, "oops", fn ->
      FunPool.run(pool, fn -> raise "oops" end)
    end

    assert FunPool.run(pool, fn -> :ok end) == :ok
  end

  test "allows parallel execution when pool size > 1" do
    name = Module.concat(__MODULE__, "ParallelPool")
    start_supervised!(FunPool.child_spec(name: name, size: 2))
    parent = self()

    spawn_link(fn ->
      FunPool.run(name, fn ->
        send(parent, :worker1_started)
        Process.sleep(100)
        send(parent, :worker1_finished)
      end)
    end)

    spawn_link(fn ->
      FunPool.run(name, fn ->
        send(parent, :worker2_started)
        Process.sleep(100)
        send(parent, :worker2_finished)
      end)
    end)

    assert_receive :worker1_started
    assert_receive :worker2_started
    assert_receive :worker1_finished, 500
    assert_receive :worker2_finished, 500
  end

  test "worker is released if caller process dies", %{pool: pool} do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        FunPool.run(pool, fn ->
          send(parent, :in_pool)
          Process.sleep(:infinity)
        end)
      end)

    assert_receive :in_pool
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    # If the worker wasn't released, this would timeout (since pool size is 1)
    assert FunPool.run(pool, fn -> :ok end, 100) == :ok
  end

  test "fails when pool does not exist" do
    assert catch_exit(FunPool.run(:non_existent_pool, fn -> :ok end)) ==
             {:noproc, {NimblePool, :checkout, [:non_existent_pool]}}
  end

  test "nested calls to the same pool deadlock if no workers available", %{pool: pool} do
    # Pool size is 1 from setup
    assert catch_exit(
             FunPool.run(
               pool,
               fn ->
                 FunPool.run(pool, fn -> :inner end, 50)
               end,
               100
             )
           ) == {:timeout, {NimblePool, :checkout, [pool]}}
  end

  test "child_spec is correct" do
    spec = FunPool.child_spec(name: :test_pool, size: 42)
    assert spec.id == :test_pool
    {NimblePool, :start_link, [opts]} = spec.start
    assert Keyword.get(opts, :name) == :test_pool
    assert Keyword.get(opts, :pool_size) == 42
  end

  test "child_spec raises if name is missing" do
    assert_raise KeyError, fn ->
      FunPool.child_spec(size: 5)
    end
  end

  test "callback coverage", %{pool: pool} do
    assert FunPool.run(pool, fn -> :ok end) == :ok
    GenServer.stop(pool)
  end

  test "can use PID instead of name" do
    pid = start_supervised!(FunPool.child_spec(name: :pid_test_pool, size: 1))
    assert FunPool.run(pid, fn -> :ok end) == :ok
  end

  test "strictly enforces max concurrency (pool size)" do
    pool_size = 3
    name = Module.concat(__MODULE__, "ConcurrencyLimitPool")
    start_supervised!(FunPool.child_spec(name: name, size: pool_size))
    parent = self()

    for i <- 1..5 do
      spawn_link(fn ->
        FunPool.run(name, fn ->
          send(parent, {:started, i})
          Process.sleep(200)
          send(parent, {:finished, i})
        end)
      end)
    end

    _ = for _ <- 1..pool_size, do: assert_receive({:started, _}, 500)

    refute_receive {:started, _}, 100

    # Since we have 5 total, and size 3:
    # Batch 1: 3 started, 2 waiting
    # Batch 2: 2 started

    assert_receive {:finished, _}, 500
    assert_receive {:started, _}, 500

    assert_receive {:finished, _}, 500
    assert_receive {:started, _}, 500

    refute_receive {:started, _}, 100
  end

  test "stress test: 100 concurrent callers on pool size 5" do
    size = 5
    name = :stress_pool
    start_supervised!(FunPool.child_spec(name: name, size: size))

    tasks =
      for i <- 1..100 do
        Task.async(fn ->
          FunPool.run(name, fn ->
            Process.sleep(10)
            i
          end)
        end)
      end

    results = Task.await_many(tasks, 5000)
    assert Enum.sort(results) == Enum.to_list(1..100)
  end

  test "handles exit(:normal) in function", %{pool: pool} do
    assert catch_exit(FunPool.run(pool, fn -> exit(:normal) end)) == :normal
    assert FunPool.run(pool, fn -> :ok end) == :ok
  end

  test "handles exit(:reason) in function", %{pool: pool} do
    assert catch_exit(FunPool.run(pool, fn -> exit(:oops) end)) == :oops
    assert FunPool.run(pool, fn -> :ok end) == :ok
  end
end
