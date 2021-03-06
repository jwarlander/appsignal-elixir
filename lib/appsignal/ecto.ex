defmodule Appsignal.Ecto do
  @moduledoc """
  Integration for logging Ecto queries

  If you're using Ecto 3, attach `Appsignal.Ecto` to Telemetry query events in
  your application's `start/2` function:

  ```
  :telemetry.attach(
    "appsignal-ecto",
    [:my_app, :repo, :query],
    &Appsignal.Ecto.handle_event/4,
    nil
  )
  ```

  For versions of Telemetry < 0.3.0, you'll need to call it slightly
  differently:

  ```
  Telemetry.attach(
    "appsignal-ecto",
    [:my_app, :repo, :query],
    Appsignal.Ecto,
    :handle_event,
    nil
  )
  ```

  On Ecto 2, add the `Appsignal.Ecto` module to your Repo's logger
  configuration instead. The `Ecto.LogEntry` logger is the default logger for
  Ecto and needs to be set as well to keep the original Ecto logger behavior
  intact.

  ```
  config :my_app, MyApp.Repo,
    loggers: [Appsignal.Ecto, Ecto.LogEntry]
  ```
  """

  require Logger

  alias Appsignal.{Transaction, TransactionRegistry}

  @nano_seconds :erlang.convert_time_unit(1, :nano_seconds, :native)

  def handle_event(_event, _latency, metadata, _config) do
    log(metadata)
  end

  def log(entry) do
    # See if we have a transaction registered for the current process
    case TransactionRegistry.lookup(self()) do
      nil ->
        # skip
        :ok

      %Transaction{} = transaction ->
        # record the event
        total_time = (entry.queue_time || 0) + (entry.query_time || 0) + (entry.decode_time || 0)
        duration = trunc(total_time / @nano_seconds)
        Transaction.record_event(transaction, "query.ecto", "", entry.query, duration, 1)
    end

    entry
  end
end
