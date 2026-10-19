defmodule LureWeb.Marks do
  @moduledoc """
  Security-printing marks drawn as SVG: guilloché rosettes (the looping line patterns on
  banknotes and certificates) and the inspection seal that carries the verdict.
  """
  use Phoenix.Component

  @doc """
  Points of a hypotrochoid, the curve a pen traces on a wheel rolling inside a ring:
  `(R - r)cos t + d cos((R - r)t / r)`, and the same with sines.
  """
  def hypotrochoid(big, small, d, cx, cy, steps \\ 720) do
    turns = div(small, Integer.gcd(big, small))

    0..steps
    |> Enum.map(fn i ->
      t = i / steps * 2 * :math.pi() * turns
      k = (big - small) / small
      x = cx + (big - small) * :math.cos(t) + d * :math.cos(k * t)
      y = cy + (big - small) * :math.sin(t) - d * :math.sin(k * t)
      "#{Float.round(x, 2)},#{Float.round(y, 2)}"
    end)
    |> then(&("M" <> Enum.join(&1, " L") <> " Z"))
  end

  attr :class, :string, default: nil
  attr :size, :integer, default: 160

  def rosette(assigns) do
    c = assigns.size / 2

    assigns =
      assign(assigns,
        paths: [
          hypotrochoid(70, 27, 40, c, c),
          hypotrochoid(70, 29, 22, c, c),
          hypotrochoid(52, 17, 30, c, c)
        ]
      )

    ~H"""
    <svg class={@class} viewBox={"0 0 #{@size} #{@size}"} aria-hidden="true">
      <path :for={p <- @paths} d={p} fill="none" stroke="currentColor" stroke-width="0.55" />
    </svg>
    """
  end

  attr :verdict, :atom, required: true

  def seal(assigns) do
    assigns = assign(assigns, ring: hypotrochoid(60, 23, 14, 66, 66, 900))

    ~H"""
    <svg class="seal" viewBox="0 0 132 132" role="img" aria-label={seal_label(@verdict)}>
      <defs>
        <path id="seal-arc" d="M66,66 m-52,0 a52,52 0 1,1 104,0 a52,52 0 1,1 -104,0" />
      </defs>
      <circle cx="66" cy="66" r="63" fill="var(--tint)" stroke="var(--tone)" stroke-width="1.5" />
      <path d={@ring} fill="none" stroke="var(--tone)" stroke-width="0.5" opacity="0.6" />
      <circle cx="66" cy="66" r="30" fill="var(--sheet)" stroke="var(--tone)" stroke-width="1.5" />
      <text fill="var(--tone)">
        <textPath href="#seal-arc" startOffset="0">{seal_ring(@verdict)}</textPath>
      </text>
      <path
        :if={@verdict == :clear}
        d="M52 66 l10 10 l19 -21"
        fill="none"
        stroke="var(--tone)"
        stroke-width="5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <g :if={@verdict == :caution} fill="var(--tone)">
        <rect x="62.5" y="48" width="7" height="22" rx="2" /><circle cx="66" cy="80" r="4" />
      </g>
      <path
        :if={@verdict == :scam}
        d="M54 54 l24 24 M78 54 l-24 24"
        stroke="var(--tone)"
        stroke-width="5"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  defp seal_label(:scam), do: "Seal: fails inspection"
  defp seal_label(:caution), do: "Seal: check before applying"
  defp seal_label(:clear), do: "Seal: passes inspection"

  defp seal_ring(:scam), do: "FAILS INSPECTION · LURE · FAILS INSPECTION · LURE ·"
  defp seal_ring(:caution), do: "CHECK BEFORE APPLYING · LURE · CHECK FIRST ·"
  defp seal_ring(:clear), do: "PASSES INSPECTION · LURE · PASSES INSPECTION ·"
end
