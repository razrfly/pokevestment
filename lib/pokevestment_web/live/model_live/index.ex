defmodule PokevestmentWeb.ModelLive.Index do
  use PokevestmentWeb, :live_view

  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.PredictionComponents

  alias Pokevestment.ML.Accountability

  @impl true
  def mount(_params, _session, socket) do
    version = Application.get_env(:pokevestment, :model_version, "v1.0.0")

    evaluation = Accountability.latest_evaluation(version)
    signal_acc = Accountability.signal_accuracy(version)
    calibration = Accountability.signal_calibration(version)
    readiness = Accountability.outcome_readiness(version)
    pipeline = Accountability.pipeline_status()
    price_range = Accountability.price_history_range()

    trust_level = compute_trust_level(evaluation, calibration, readiness, price_range)

    {:ok,
     assign(socket,
       page_title: "Model Accountability",
       evaluation: evaluation,
       signal_accuracy: signal_acc,
       calibration: calibration,
       readiness: readiness,
       pipeline: pipeline,
       price_range: price_range,
       trust_level: trust_level
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Trust Level Banner --%>
    <.section class="pt-24 sm:pt-32">
      <.container>
        <.eyebrow>Model accountability</.eyebrow>
        <.heading class="mt-2">
          How trustworthy are these predictions?
        </.heading>
        <.trust_banner level={@trust_level} />
      </.container>
    </.section>

    <%!-- Training Metrics --%>
    <.section class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Training metrics</.eyebrow>
        <.heading class="mt-2 text-3xl sm:text-4xl">
          Model Performance
        </.heading>
        <.training_metrics evaluation={@evaluation} />
      </.container>
    </.section>

    <%!-- Signal Accuracy --%>
    <.section class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Real-world accuracy</.eyebrow>
        <.heading class="mt-2 text-3xl sm:text-4xl">
          Signal Accuracy
        </.heading>
        <.signal_accuracy_section
          accuracy={@signal_accuracy}
          calibration={@calibration}
          readiness={@readiness}
        />
      </.container>
    </.section>

    <%!-- Feature Importance --%>
    <.section :if={@evaluation && @evaluation.umbrella_importances} class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>What drives predictions</.eyebrow>
        <.heading class="mt-2 text-3xl sm:text-4xl">
          Feature Importance
        </.heading>
        <div class="mt-10 grid grid-cols-1 gap-8 lg:grid-cols-2">
          <.card title="Umbrella Categories">
            <.umbrella_breakdown breakdown={@evaluation.umbrella_importances} />
          </.card>
          <.card :if={@evaluation.feature_importances} title="Top Individual Features">
            <.top_features features={@evaluation.feature_importances} />
          </.card>
        </div>
      </.container>
    </.section>

    <%!-- Pipeline Health --%>
    <.section class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Infrastructure</.eyebrow>
        <.heading class="mt-2 text-3xl sm:text-4xl">
          Pipeline Health
        </.heading>
        <.pipeline_health pipeline={@pipeline} />
      </.container>
    </.section>

    <%!-- Accountability Checklist --%>
    <.section class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Transparency</.eyebrow>
        <.heading class="mt-2 text-3xl sm:text-4xl">
          Accountability Checklist
        </.heading>
        <.checklist
          evaluation={@evaluation}
          readiness={@readiness}
          signal_accuracy={@signal_accuracy}
        />
      </.container>
    </.section>
    """
  end

  # --- Private function components ---

  attr :level, :atom, required: true

  defp trust_banner(assigns) do
    {color, icon, label, description} =
      case assigns.level do
        :high ->
          {"border-emerald-300 bg-emerald-50 dark:border-emerald-800 dark:bg-emerald-950/40",
           "text-emerald-600 dark:text-emerald-400", "HIGH",
           "Model has been validated with real outcome data and meets accountability criteria."}

        :medium ->
          {"border-amber-300 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/40",
           "text-amber-600 dark:text-amber-400", "MEDIUM",
           "Model has training metrics but limited real-world validation. Treat signals as directional, not definitive."}

        :low ->
          {"border-red-300 bg-red-50 dark:border-red-800 dark:bg-red-950/40",
           "text-red-600 dark:text-red-400", "LOW",
           "Model has not yet been validated against real outcomes. Predictions are experimental."}
      end

    assigns =
      assign(assigns,
        color: color,
        icon: icon,
        label: label,
        description: description
      )

    ~H"""
    <div class={["mt-8 rounded-2xl border p-6", @color]}>
      <div class="flex items-start gap-4">
        <div class={["text-2xl font-bold", @icon]}>
          {@label}
        </div>
        <p class="text-sm text-olive-700 dark:text-olive-300">
          {@description}
        </p>
      </div>
    </div>
    """
  end

  attr :evaluation, :any, required: true

  defp training_metrics(%{evaluation: nil} = assigns) do
    ~H"""
    <div class="mt-10">
      <.card title="No model evaluation recorded yet">
        <p class="text-sm text-olive-600 dark:text-olive-400">
          Run the ML pipeline to generate training metrics.
        </p>
      </.card>
    </div>
    """
  end

  defp training_metrics(assigns) do
    ~H"""
    <div class="mt-10 grid grid-cols-2 gap-4 sm:grid-cols-4">
      <.metric_card
        label="R-squared"
        value={format_metric(@evaluation.r_squared)}
        baseline={format_metric(@evaluation.baseline_r_squared)}
        good={decimal_gt?(@evaluation.r_squared, @evaluation.baseline_r_squared)}
      />
      <.metric_card
        label="RMSE"
        value={format_metric(@evaluation.rmse)}
        baseline={format_metric(@evaluation.baseline_rmse)}
        good={decimal_lt?(@evaluation.rmse, @evaluation.baseline_rmse)}
      />
      <.metric_card
        label="MAE"
        value={format_metric(@evaluation.mae)}
        baseline={nil}
        good={nil}
      />
      <.metric_card
        label="MAPE"
        value={format_metric(@evaluation.mape)}
        baseline={nil}
        good={nil}
      />
    </div>
    <div class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
      <.info_card label="Split Strategy" value={@evaluation.split_strategy || "random"} />
      <.info_card label="Train Rows" value={format_number(@evaluation.train_rows)} />
      <.info_card label="Val Rows" value={format_number(@evaluation.val_rows)} />
      <.info_card label="Evaluated" value={Calendar.strftime(@evaluation.evaluation_date, "%b %d, %Y")} />
    </div>
    <div :if={@evaluation.split_strategy == "random"} class="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-950/40">
      <p class="text-sm text-amber-800 dark:text-amber-300">
        This model uses a random 80/20 split, which can cause data leakage (future data in training set). Temporal split is recommended for production.
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :baseline, :any, default: nil
  attr :good, :any, default: nil

  defp metric_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40">
      <p class="text-xs font-medium uppercase tracking-wide text-olive-500 dark:text-olive-400">
        {@label}
      </p>
      <p class="mt-2 font-display text-2xl font-medium tracking-tight text-olive-950 dark:text-white">
        {@value}
      </p>
      <p :if={@baseline} class="mt-1 text-xs text-olive-500 dark:text-olive-500">
        Baseline: {@baseline}
        <span :if={@good == true} class="ml-1 text-emerald-600 dark:text-emerald-400">Better</span>
        <span :if={@good == false} class="ml-1 text-red-600 dark:text-red-400">Worse</span>
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp info_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40">
      <p class="text-xs font-medium uppercase tracking-wide text-olive-500 dark:text-olive-400">
        {@label}
      </p>
      <p class="mt-2 font-display text-lg font-medium text-olive-950 dark:text-white">
        {@value}
      </p>
    </div>
    """
  end

  attr :accuracy, :map, required: true
  attr :calibration, :map, required: true
  attr :readiness, :map, required: true

  defp signal_accuracy_section(%{accuracy: acc} = assigns) when acc == %{} do
    ~H"""
    <div class="mt-10">
      <.card title="Waiting for outcome data">
        <p class="text-sm text-olive-600 dark:text-olive-400">
          Signal accuracy will appear here once predictions are 30 days old and outcome prices are available.
        </p>
        <div :if={@readiness.earliest_maturity} class="mt-4">
          <p class="text-sm text-olive-500 dark:text-olive-500">
            First outcomes expected: <span class="font-medium text-olive-700 dark:text-olive-300">{Calendar.strftime(@readiness.earliest_maturity, "%B %d, %Y")}</span>
          </p>
        </div>
        <div class="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3">
          <.info_card label="Pending Evaluation" value={format_number(@readiness.pending_evaluation)} />
          <.info_card label="Already Evaluated" value={format_number(@readiness.evaluated)} />
          <.info_card label="Mature Snapshots" value={format_number(@readiness.mature_snapshots)} />
        </div>
      </.card>
    </div>
    """
  end

  defp signal_accuracy_section(assigns) do
    signals = ["STRONG_BUY", "BUY", "HOLD", "OVERVALUED"]

    rows =
      Enum.map(signals, fn signal ->
        acc = Map.get(assigns.accuracy, signal, %{total: 0, correct: 0, accuracy: 0.0})
        cal = Map.get(assigns.calibration, signal, %{mean_return: 0.0, median_return: 0.0})
        {signal, acc, cal}
      end)

    assigns = assign(assigns, rows: rows)

    ~H"""
    <div class="mt-10 overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-olive-200 dark:border-olive-800">
            <th class="pb-3 text-left font-medium text-olive-700 dark:text-olive-400">Signal</th>
            <th class="pb-3 text-right font-medium text-olive-700 dark:text-olive-400">Total</th>
            <th class="pb-3 text-right font-medium text-olive-700 dark:text-olive-400">Correct</th>
            <th class="pb-3 text-right font-medium text-olive-700 dark:text-olive-400">Accuracy</th>
            <th class="pb-3 text-right font-medium text-olive-700 dark:text-olive-400">Mean Return</th>
            <th class="pb-3 text-right font-medium text-olive-700 dark:text-olive-400">Median Return</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{signal, acc, cal} <- @rows} class="border-b border-olive-100 dark:border-olive-800/50">
            <td class="py-3">
              <.signal_badge signal={signal} />
            </td>
            <td class="py-3 text-right tabular-nums text-olive-900 dark:text-olive-200">{acc.total}</td>
            <td class="py-3 text-right tabular-nums text-olive-900 dark:text-olive-200">{acc.correct}</td>
            <td class="py-3 text-right tabular-nums font-medium">
              <span class={accuracy_color(acc.accuracy)}>{format_pct(acc.accuracy)}</span>
            </td>
            <td class="py-3 text-right tabular-nums text-olive-900 dark:text-olive-200">{format_return(cal.mean_return)}</td>
            <td class="py-3 text-right tabular-nums text-olive-900 dark:text-olive-200">{format_return(cal.median_return)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :features, :map, required: true

  defp top_features(assigns) do
    sorted =
      assigns.features
      |> Enum.sort_by(fn {_k, v} -> -abs(to_float(v)) end)
      |> Enum.take(10)

    max_val =
      sorted
      |> Enum.map(fn {_k, v} -> abs(to_float(v)) end)
      |> Enum.max(fn -> 1.0 end)

    assigns = assign(assigns, sorted: sorted, max_val: max_val)

    ~H"""
    <div class="space-y-2">
      <div :for={{feature, value} <- @sorted} class="flex items-center gap-2">
        <span class="w-40 truncate text-xs text-olive-700 dark:text-olive-400">
          {humanize(feature)}
        </span>
        <div class="flex-1">
          <div class="h-2 rounded-full bg-olive-200 dark:bg-olive-800">
            <div
              class="h-2 rounded-full bg-olive-600 dark:bg-olive-400"
              style={"width: #{bar_pct(value, @max_val)}%"}
            />
          </div>
        </div>
        <span class="w-14 text-right text-xs tabular-nums text-olive-600 dark:text-olive-500">
          {format_importance(value)}
        </span>
      </div>
    </div>
    """
  end

  attr :pipeline, :list, required: true

  defp pipeline_health(assigns) do
    workers = [
      {"Pokevestment.Workers.DailyPriceSync", "Price Sync"},
      {"Pokevestment.Workers.TournamentSync", "Tournament Sync"},
      {"Pokevestment.Workers.DailyPrediction", "ML Predictions"},
      {"Pokevestment.Workers.OutcomeEvaluator", "Outcome Evaluator"}
    ]

    rows =
      Enum.map(workers, fn {worker_class, label} ->
        job = Enum.find(assigns.pipeline, &(&1.worker == worker_class))
        {label, job}
      end)

    assigns = assign(assigns, rows: rows)

    ~H"""
    <div class="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <div
        :for={{label, job} <- @rows}
        class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40"
      >
        <p class="text-xs font-medium uppercase tracking-wide text-olive-500 dark:text-olive-400">
          {label}
        </p>
        <div :if={job} class="mt-2">
          <p class="text-sm font-medium text-olive-950 dark:text-white">
            <.job_status_badge state={job.state} />
          </p>
          <p :if={job.completed_at} class="mt-1 text-xs text-olive-500 dark:text-olive-500">
            {format_datetime(job.completed_at)}
          </p>
        </div>
        <p :if={is_nil(job)} class="mt-2 text-sm text-olive-400 dark:text-olive-600">
          Never run
        </p>
      </div>
    </div>
    """
  end

  attr :state, :string, required: true

  defp job_status_badge(%{state: "completed"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-emerald-600 dark:text-emerald-400">
      <span class="h-2 w-2 rounded-full bg-emerald-500" /> Completed
    </span>
    """
  end

  defp job_status_badge(%{state: "executing"} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-blue-600 dark:text-blue-400">
      <span class="h-2 w-2 animate-pulse rounded-full bg-blue-500" /> Running
    </span>
    """
  end

  defp job_status_badge(%{state: state} = assigns) do
    assigns = assign(assigns, state: state)

    ~H"""
    <span class="inline-flex items-center gap-1 text-olive-600 dark:text-olive-400">
      <span class="h-2 w-2 rounded-full bg-olive-400" /> {@state}
    </span>
    """
  end

  attr :evaluation, :any, required: true
  attr :readiness, :map, required: true
  attr :signal_accuracy, :map, required: true

  defp checklist(assigns) do
    has_eval = not is_nil(assigns.evaluation)

    checks = [
      {
        "Model evaluation metrics recorded per run",
        has_eval,
        :pass,
        "Training metrics (R², RMSE, MAE, MAPE) stored for each pipeline run."
      },
      {
        "Baseline comparison (mean predictor) logged",
        has_eval and not is_nil(assigns.evaluation.baseline_r_squared),
        :pass,
        "Model is compared against a naive mean-prediction baseline."
      },
      {
        "SHAP feature importances computed per run",
        has_eval and not is_nil(assigns.evaluation.umbrella_importances),
        :pass,
        "Feature importance breakdown available for model interpretability."
      },
      {
        "Prediction snapshots stored (append-only)",
        assigns.readiness.mature_snapshots > 0 or assigns.readiness.pending_evaluation > 0 or assigns.readiness.evaluated > 0 or (has_eval and assigns.evaluation.train_rows > 0),
        :pass,
        "Immutable prediction records preserved for future accountability."
      },
      {
        "Outcome tracking deployed, awaiting 30-day maturity",
        assigns.readiness.evaluated > 0,
        :waiting,
        "OutcomeEvaluator runs daily. First outcomes expected #{if assigns.readiness.earliest_maturity, do: Calendar.strftime(assigns.readiness.earliest_maturity, "%B %d, %Y"), else: "when predictions mature"}."
      },
      {
        "Temporal train/val split",
        has_eval and assigns.evaluation.split_strategy == "temporal",
        :fail,
        "Newest cards used for validation, preventing future data leakage."
      },
      {
        "Walk-forward backtest",
        false,
        :fail,
        "Blocked on 60+ days of price data (~May 28). Will validate predictions on truly unseen future data."
      },
      {
        "Sacred holdout set",
        false,
        :fail,
        "Blocked on 60+ days of price data (~May 28). A set of cards never seen during training."
      }
    ]

    assigns = assign(assigns, checks: checks)

    ~H"""
    <div class="mt-10">
      <div class="space-y-3">
        <div
          :for={{label, passed, status, description} <- @checks}
          class="flex items-start gap-3 rounded-xl border border-olive-200 bg-white/60 p-4 dark:border-olive-800 dark:bg-olive-900/40"
        >
          <div class={[
            "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs font-bold",
            checklist_icon_class(passed, status)
          ]}>
            <span :if={passed}>&#10003;</span>
            <span :if={not passed and status == :waiting}>&#8987;</span>
            <span :if={not passed and status != :waiting}>&#10007;</span>
          </div>
          <div>
            <p class={[
              "text-sm font-medium",
              if(passed,
                do: "text-olive-950 dark:text-white",
                else: "text-olive-500 dark:text-olive-500"
              )
            ]}>
              {label}
            </p>
            <p class="mt-0.5 text-xs text-olive-500 dark:text-olive-500">
              {description}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-olive-200 bg-white/60 p-6 dark:border-olive-800 dark:bg-olive-900/40">
      <h3 class="font-display text-lg font-medium text-olive-950 dark:text-white">
        {@title}
      </h3>
      <div class="mt-4">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp compute_trust_level(evaluation, calibration, readiness, _price_range) do
    # Issue #67 trust criteria:
    # 1. Temporal split active (not random)
    # 2. 30-day outcomes exist (>100 evaluated)
    # 3. Signal calibration passes (returns monotonically ordered)
    # 4. Walk-forward backtest exists (deferred — always false for now)
    # 5. Sacred holdout evaluated (deferred — always false for now)
    checks = [
      not is_nil(evaluation) and evaluation.split_strategy != "random",
      readiness.evaluated > 100,
      signal_calibration_passes?(calibration),
      false,
      false
    ]

    score = Enum.count(checks, & &1)

    cond do
      score >= 4 -> :high
      score >= 2 -> :medium
      true -> :low
    end
  end

  defp decimal_gt?(nil, _), do: false
  defp decimal_gt?(_, nil), do: false

  defp decimal_gt?(%Decimal{} = a, %Decimal{} = b),
    do: Decimal.compare(a, b) == :gt

  defp decimal_gt?(_, _), do: false

  defp decimal_lt?(nil, _), do: false
  defp decimal_lt?(_, nil), do: false

  defp decimal_lt?(%Decimal{} = a, %Decimal{} = b),
    do: Decimal.compare(a, b) == :lt

  defp decimal_lt?(_, _), do: false

  defp signal_calibration_passes?(cal) when cal == %{}, do: false

  defp signal_calibration_passes?(cal) do
    # Signal calibration passes if mean returns are monotonically ordered:
    # STRONG_BUY > BUY > HOLD > OVERVALUED
    get_return = fn signal -> Map.get(cal, signal, %{mean_return: 0.0}) |> Map.get(:mean_return, 0.0) end

    sb = get_return.("STRONG_BUY")
    b = get_return.("BUY")
    h = get_return.("HOLD")
    o = get_return.("OVERVALUED")

    sb > b and b > h and h > o
  end

  defp checklist_icon_class(true, _),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400"

  defp checklist_icon_class(false, :waiting),
    do: "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-400"

  defp checklist_icon_class(false, _),
    do: "bg-olive-100 text-olive-400 dark:bg-olive-800 dark:text-olive-600"

  defp format_metric(nil), do: "--"
  defp format_metric(%Decimal{} = d), do: Decimal.round(d, 4) |> Decimal.to_string()

  defp format_number(nil), do: "0"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)

  defp format_pct(n) when is_float(n), do: "#{:erlang.float_to_binary(n, decimals: 1)}%"
  defp format_pct(_), do: "--"

  defp format_return(n) when is_float(n) do
    sign = if n >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(n * 100, decimals: 1)}%"
  end

  defp format_return(_), do: "--"

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%b %d at %H:%M UTC")
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d at %H:%M UTC")
  end

  defp format_datetime(_), do: "--"

  defp accuracy_color(n) when is_float(n) and n >= 60,
    do: "text-emerald-600 dark:text-emerald-400"

  defp accuracy_color(n) when is_float(n) and n >= 45,
    do: "text-amber-600 dark:text-amber-400"

  defp accuracy_color(_), do: "text-red-600 dark:text-red-400"

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n / 1
  defp to_float(_), do: 0.0

  defp bar_pct(value, max_val) when max_val > 0 do
    (abs(to_float(value)) / max_val * 100) |> Float.round(1)
  end

  defp bar_pct(_, _), do: 0

  defp format_importance(value) do
    v = to_float(value)
    :erlang.float_to_binary(v * 100, decimals: 1) <> "%"
  end

  defp humanize(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
