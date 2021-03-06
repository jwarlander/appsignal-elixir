defmodule AppsignalTransactionTest do
  use ExUnit.Case
  import AppsignalTest.Utils

  alias Appsignal.{Transaction, TransactionRegistry}

  test "transaction lifecycle" do
    transaction = Transaction.start("test1", :http_request)
    assert %Transaction{} = transaction

    assert ^transaction = Transaction.start_event(transaction)

    assert ^transaction =
             Transaction.finish_event(
               transaction,
               "sql.query",
               "Model load",
               "SELECT * FROM table;",
               1
             )

    assert ^transaction =
             Transaction.record_event(
               transaction,
               "sql.query",
               "Model load",
               "SELECT * FROM table;",
               1000 * 1000 * 3,
               1
             )

    assert ^transaction =
             Transaction.set_error(transaction, "Error", "error message", System.stacktrace())

    assert ^transaction = Transaction.set_sample_data(transaction, "key", %{user_id: 1})
    assert ^transaction = Transaction.set_action(transaction, "GET:/")
    assert ^transaction = Transaction.set_queue_start(transaction, 1000)
    assert ^transaction = Transaction.set_meta_data(transaction, "email", "info@info.com")
    assert [:sample, :no_sample] |> Enum.member?(Transaction.finish(transaction))
    assert :ok = Transaction.complete(transaction)
  end

  test "use default transaction in Transaction calls" do
    transaction = Transaction.start("test2", :http_request)
    assert %Transaction{} = transaction

    assert ^transaction = Transaction.start_event()

    assert ^transaction =
             Transaction.finish_event("sql.query", "Model load", "SELECT * FROM table;", 1)

    assert ^transaction =
             Transaction.record_event(
               "sql.query",
               "Model load",
               "SELECT * FROM table;",
               1000 * 1000 * 3,
               1
             )

    assert ^transaction = Transaction.set_error("Error", "error message", System.stacktrace())
    assert ^transaction = Transaction.set_sample_data("key", %{user_id: 1})
    assert ^transaction = Transaction.set_action("GET:/")
    assert ^transaction = Transaction.set_queue_start(1000)
    assert ^transaction = Transaction.set_meta_data("email", "info@info.com")
    assert [:sample, :no_sample] |> Enum.member?(Transaction.finish())
    assert :ok = Transaction.complete()
  end

  test "returns nil in simplified Transaction calls when no current transaction" do
    assert nil == Transaction.start_event()
    assert nil == Transaction.finish_event("sql.query", "Model load", "SELECT * FROM table;", 1)

    assert nil ==
             Transaction.record_event(
               "sql.query",
               "Model load",
               "SELECT * FROM table;",
               1000 * 1000 * 3,
               1
             )

    assert nil == Transaction.set_error("Error", "error message", "['backtrace']")
    assert nil == Transaction.set_sample_data("key", "{'user_id': 1}")
    assert nil == Transaction.set_action("GET:/")
    assert nil == Transaction.set_queue_start(1000)

    assert nil == Transaction.set_meta_data("email", "info@info.com")
    assert nil == Transaction.set_meta_data(email: "email@email.com")
    assert nil == Transaction.set_meta_data(%{"foo" => "bar", "value" => 123})

    assert nil == Transaction.finish()
    assert nil == Transaction.complete()
  end

  @tag :skip_env_test_no_nif
  test "use shorthand set_meta_data function" do
    transaction = Transaction.start("test3", :http_request)
    assert %Transaction{} = transaction
    Transaction.set_meta_data(email: "alice@example.com")
    Transaction.set_meta_data(%{"foo" => "bar", "value" => 123})

    assert %{"metadata" => %{"email" => "alice@example.com", "foo" => "bar", "value" => "123"}} =
             Transaction.to_map(transaction)
  end

  test "data encoding" do
    transaction = Transaction.start("test3", :http_request)

    # Map
    assert ^transaction = Transaction.set_sample_data("key", %{"user_id" => 1})

    # Atom
    assert ^transaction = Transaction.set_sample_data("key", %{user_id: 1})

    # complex
    assert ^transaction = Transaction.set_sample_data("key", %{values: %{1 => 2, 3 => 4}})
  end

  test "finishing an event with a non-string body" do
    transaction = Transaction.start("test4", :http_request)
    assert %Transaction{} = transaction

    assert ^transaction = Transaction.start_event(transaction)

    assert ^transaction =
             Transaction.finish_event(
               transaction,
               "render.phoenix_controller",
               "phoenix_controller_render",
               %{format: "html", template: "index.html"},
               0
             )
  end

  test "handles unformatted stacktraces" do
    transaction = Transaction.start("test1", :http_request)

    stacktrace = [
      {:elixir_translator, :guard_op, 2, [file: 'src/elixir_translator.erl', line: 317]}
    ]

    assert ^transaction = Transaction.set_error(transaction, "Error", "error message", stacktrace)
    assert ^transaction = Transaction.start_event(transaction)

    assert ^transaction =
             Transaction.finish_event(
               transaction,
               "render.phoenix_controller",
               "phoenix_controller_render",
               %{format: "html", template: "index.html"},
               0
             )
  end

  describe "concerning metadata" do
    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "sets the request metadata" do
      conn =
        %Plug.Conn{request_path: "/pa/th", method: "GET"}
        |> Plug.Conn.put_private(:plug_session, %{})
        |> Plug.Conn.put_private(:plug_session_fetch, :done)

      transaction =
        "test5"
        |> Transaction.start(:http_request)
        |> Transaction.set_request_metadata(conn)

      assert %{"metadata" => %{"path" => "/pa/th", "method" => "GET"}} =
               Transaction.to_map(transaction)
    end
  end

  describe "concerning skipping session data" do
    setup do
      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:plug_session, %{})
        |> Plug.Conn.put_private(:plug_session_fetch, :done)

      {:ok, conn: conn}
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "sends session data", %{conn: conn} do
      transaction =
        "test5"
        |> Transaction.start(:http_request)
        |> Transaction.set_request_metadata(conn)

      assert %{"sample_data" => %{"session_data" => session_data}} =
               Transaction.to_map(transaction)

      assert session_data == conn.private.plug_session
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "sends session data when skip_session_data is false", %{conn: conn} do
      transaction =
        with_config(%{skip_session_data: false}, fn ->
          "test5"
          |> Transaction.start(:http_request)
          |> Transaction.set_request_metadata(conn)
        end)

      assert %{"sample_data" => %{"session_data" => session_data}} =
               Transaction.to_map(transaction)

      assert session_data == conn.private.plug_session
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "does not send session data when skip_session_data is true", %{conn: conn} do
      transaction =
        with_config(%{skip_session_data: true}, fn ->
          "test5"
          |> Transaction.start(:http_request)
          |> Transaction.set_request_metadata(conn)
        end)

      %{"sample_data" => sample_data} = Transaction.to_map(transaction)
      refute sample_data["session_data"]
    end
  end

  describe "concerning filtering session data" do
    setup do
      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:plug_session, %{"password" => "secret", "foo" => "bar"})
        |> Plug.Conn.put_private(:plug_session_fetch, :done)

      {:ok, conn: conn}
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "takes out filtered session keys", %{conn: conn} do
      transaction =
        with_config(%{filter_session_data: ~w(password)}, fn ->
          "test5"
          |> Transaction.start(:http_request)
          |> Transaction.set_request_metadata(conn)
        end)

      assert %{"sample_data" => %{"session_data" => session_data}} =
               Transaction.to_map(transaction)

      assert session_data == %{"foo" => "bar", "password" => "[FILTERED]"}
    end
  end

  describe "concerning filtering params" do
    setup do
      conn = %Plug.Conn{params: %{"foo" => "bar", "password" => "secret"}}

      {:ok, conn: conn}
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "when send_params=true it sets params keys", %{conn: conn} do
      transaction =
        with_config(%{send_params: true}, fn ->
          "test5"
          |> Transaction.start(:http_request)
          |> Transaction.set_request_metadata(conn)
        end)

      assert %{"sample_data" => %{"params" => params}} = Transaction.to_map(transaction)

      assert params == %{"foo" => "bar", "password" => "[FILTERED]"}
    end

    @tag :skip_env_test_no_nif
    @tag :skip_env_test
    test "when send_params=false it doesn't set params keys", %{conn: conn} do
      transaction =
        with_config(%{send_params: false}, fn ->
          "test5"
          |> Transaction.start(:http_request)
          |> Transaction.set_request_metadata(conn)
        end)

      refute Map.has_key?(Transaction.to_map(transaction), "params")
    end
  end

  describe "creating a transaction" do
    setup do
      id = Transaction.generate_id()
      [id: id, transaction: Transaction.create(id, :http_request)]
    end

    test "returns a transaction", %{transaction: transaction} do
      assert %Transaction{} = transaction
    end

    test "uses the passed transaction ID", %{id: id, transaction: transaction} do
      assert %{id: ^id} = transaction
    end

    test "creates a transaction_reference", %{transaction: transaction} do
      assert is_reference_or_binary(transaction.resource)
    end
  end

  describe "starting a transaction" do
    setup do
      id = Transaction.generate_id()
      [id: id, transaction: Transaction.start(id, :http_request)]
    end

    test "creates a transaction", %{transaction: transaction, id: id} do
      assert %Transaction{id: ^id} = transaction
    end

    test "registers the transaction", %{transaction: transaction} do
      assert :ok == TransactionRegistry.remove_transaction(transaction)
    end
  end

  describe "completing a transaction" do
    test "removes the transaction from the registry" do
      transaction = Transaction.start(Transaction.generate_id(), :http_request)
      Transaction.finish(transaction)
      :ok = Transaction.complete(transaction)
      {:error, :not_found} = TransactionRegistry.remove_transaction(transaction)
    end
  end

  describe "setting a transaction's action name" do
    @tag :skip_env_test_no_nif
    test "stores the action name on the transaction" do
      transaction = Transaction.create(Transaction.generate_id(), :http_request)
      Transaction.set_action(transaction, "ActionController#my_action")

      assert Transaction.to_map(transaction)["action"] == "ActionController#my_action"
    end
  end

  describe "when the registry is not running" do
    setup do
      transaction = Transaction.start(Transaction.generate_id(), :http_request)
      :ok = Supervisor.terminate_child(Appsignal.Supervisor, TransactionRegistry)

      on_exit(fn ->
        {:ok, _} = Supervisor.restart_child(Appsignal.Supervisor, TransactionRegistry)
      end)

      [transaction: transaction]
    end

    test "creates a transaction" do
      id = Transaction.generate_id()
      transaction = Transaction.start(id, :http_request)

      assert %Transaction{id: ^id} = transaction
    end

    test "does not crash when trying to complete a transaction", %{transaction: transaction} do
      assert :ok == Transaction.complete(transaction)
    end
  end

  describe "setting a transaction's namespace" do
    @tag :skip_env_test_no_nif
    test "overwrites the transaction's namespace with an atom" do
      transaction = Transaction.create(Transaction.generate_id(), :http_request)
      Transaction.set_namespace(transaction, :background)

      assert Transaction.to_map(transaction)["namespace"] == "background"
    end

    @tag :skip_env_test_no_nif
    test "overwrites the transaction's namespace with a string" do
      transaction = Transaction.create(Transaction.generate_id(), :http_request)
      Transaction.set_namespace(transaction, "background")

      assert Transaction.to_map(transaction)["namespace"] == "background"
    end
  end
end
