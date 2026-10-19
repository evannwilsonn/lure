defmodule LureWeb.Marks do
  @moduledoc """
  The engraved plate the page is drawn on, after the project's thumbnail ("Still Water"):
  horizontal hatching that thickens with depth, ripples where a fishing line breaks the
  surface, a hook drawn in line, an orange bait slip, and a depth ruler. The verdict figure
  reuses the same pieces: what the hook carries says what Lure found.
  """
  use Phoenix.Component

  @doc """
  Hatching lines for a band of water `height` units deep: each line wavers a little (a slow
  sine of x and depth), and lines get closer, darker and heavier the deeper they sit.
  Returns `{path, opacity, width}` tuples.
  """
  def hatching(width, height, top \\ 0, first_gap \\ 9.0) do
    Stream.unfold({top + first_gap, first_gap}, fn {y, gap} ->
      if y >= height do
        nil
      else
        depth = (y - top) / (height - top)

        d =
          for x <- 0..width//24, into: "M0 #{fmt(y)}" do
            " L#{x} #{fmt(y + :math.sin(x / 97 + y / 31) * 1.1)}"
          end

        next_gap = max(3.4, gap * 0.955)
        {{d, fmt(0.07 + 0.22 * depth), fmt(0.6 + 0.5 * depth)}, {y + next_gap, next_gap}}
      end
    end)
    |> Enum.to_list()
  end

  defp fmt(x), do: Float.round(x * 1.0, 2)

  @doc "A full-width band of engraved water; it stretches sideways, the lines never get thicker."
  attr :class, :string, default: nil

  def water(assigns) do
    assigns = assign(assigns, lines: hatching(1200, 300))

    ~H"""
    <svg class={@class} viewBox="0 0 1200 300" preserveAspectRatio="none" aria-hidden="true">
      <path
        :for={{d, op, w} <- @lines}
        d={d}
        fill="none"
        stroke="var(--hatch)"
        stroke-opacity={op}
        stroke-width={w}
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  @doc """
  The rig from the thumbnail: the line coming down through the surface (at x = 300, the
  surface at y = 30), ripples half above and half below, a hook, and the bait slip on its point.
  """
  attr :class, :string, default: nil

  def rig(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 480 300" aria-hidden="true">
      <g fill="none" stroke-width="1">
        <%= for {r, i} <- Enum.with_index([16, 36, 62, 94, 132, 176]) do %>
          <path
            d={"M#{300 - r} 30 A#{r} #{r * 0.13} 0 0 1 #{300 + r} 30"}
            stroke="var(--line-above)"
            stroke-opacity={0.75 - i * 0.11}
          />
          <path
            d={"M#{300 - r} 30 A#{r} #{r * 0.13} 0 0 0 #{300 + r} 30"}
            stroke="var(--cream)"
            stroke-opacity={0.6 - i * 0.09}
          />
        <% end %>
      </g>
      <line x1="300" y1="0" x2="300" y2="30" stroke="var(--line-above)" stroke-width="1.1" />
      <line x1="300" y1="30" x2="300" y2="146" stroke="var(--cream)" stroke-width="1.1" />
      <g class="hook">
        <g transform="translate(150 196) rotate(-7)">
          <rect width="104" height="38" fill="var(--bait)" />
          <path d="M104 0 L104 38 L92 38 Z" fill="var(--bait-fold)" />
          <text x="8" y="16" class="slip-a">EARN $5,000/WK</text>
          <text x="8" y="29" class="slip-b">NO EXPERIENCE</text>
        </g>
        <g fill="none" stroke="var(--cream)" stroke-linecap="round" stroke-linejoin="round">
          <ellipse cx="300" cy="152" rx="5" ry="7" stroke-width="2.4" />
          <path d="M300 159 L300 226 C300 266 236 268 234 228 L234 204" stroke-width="3.2" />
          <path d="M234 204 L243 218" stroke-width="2.4" />
        </g>
      </g>
    </svg>
    """
  end

  @doc "The depth ruler down the right edge of the water."
  attr :class, :string, default: nil

  def ruler(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 70 300" aria-hidden="true">
      <%= for i <- 0..7 do %>
        <line
          x1="40"
          y1={4 + i * 40}
          x2={if rem(i, 2) == 1, do: 50, else: 56}
          y2={4 + i * 40}
          stroke="var(--cream)"
          stroke-opacity=".55"
        />
        <text
          :if={rem(i, 2) == 0 and i > 0}
          x="32"
          y={7 + i * 40}
          text-anchor="end"
          class="depth"
        >
          {i} m
        </text>
      <% end %>
    </svg>
    """
  end

  @doc """
  The verdict as a figure: still water with a line through it. A real ad leaves the line
  bare, an ad to check has a hook on it, and a scam has the hook baited.
  """
  attr :verdict, :atom, required: true

  def seal(assigns) do
    assigns = assign(assigns, lines: hatching(132, 132, 66, 6.0))

    ~H"""
    <svg class="seal" viewBox="0 0 132 132" role="img" aria-label={seal_label(@verdict)}>
      <.pool lines={@lines} />
      <line x1="80" y1="0" x2="80" y2="66" stroke="var(--line-above)" stroke-width="1.2" />
      <line
        x1="80"
        y1="66"
        x2="80"
        y2={if @verdict == :clear, do: 104, else: 82}
        stroke="var(--cream)"
        stroke-width="1.2"
      />
      <g
        :if={@verdict in [:caution, :scam]}
        fill="none"
        stroke="var(--cream)"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <ellipse cx="80" cy="85" rx="3" ry="4" stroke-width="1.8" />
        <path d="M80 89 L80 106 C80 124 56 125 55 107 L55 98" stroke-width="2.4" />
        <path d="M55 98 L60 106" stroke-width="1.8" />
      </g>
      <g :if={@verdict == :scam} transform="translate(14 96) rotate(-7)">
        <rect width="40" height="16" fill="var(--bait)" />
        <path d="M40 0 L40 16 L35 16 Z" fill="var(--bait-fold)" />
        <text x="4" y="11" class="slip-a" style="font-size: 7.5px">$$$</text>
      </g>
    </svg>
    """
  end

  @doc "The figure before anything is checked: the water, undisturbed."
  def still(assigns) do
    assigns = assign(assigns, lines: hatching(132, 132, 66, 6.0))

    ~H"""
    <svg class="seal seal-blank" viewBox="0 0 132 132" aria-hidden="true">
      <.pool lines={@lines} ripples={false} />
      <text x="66" y="48" text-anchor="middle">AWAITING</text>
    </svg>
    """
  end

  attr :lines, :list, required: true
  attr :ripples, :boolean, default: true

  defp pool(assigns) do
    ~H"""
    <rect x="0" y="66" width="132" height="66" fill="var(--water)" />
    <path
      :for={{d, op, w} <- @lines}
      d={d}
      fill="none"
      stroke="var(--hatch)"
      stroke-opacity={op}
      stroke-width={w}
    />
    <g :if={@ripples} fill="none" stroke-width="0.8">
      <%= for {r, i} <- Enum.with_index([6, 14, 24, 36, 50]) do %>
        <path
          d={"M#{80 - r} 66 A#{r} #{r * 0.15} 0 0 1 #{80 + r} 66"}
          stroke="var(--line-above)"
          stroke-opacity={0.75 - i * 0.13}
        />
        <path
          d={"M#{80 - r} 66 A#{r} #{r * 0.15} 0 0 0 #{80 + r} 66"}
          stroke="var(--cream)"
          stroke-opacity={0.7 - i * 0.12}
        />
      <% end %>
    </g>
    """
  end

  defp seal_label(:scam), do: "Figure: the hook is baited. Fails inspection"
  defp seal_label(:caution), do: "Figure: a hook on the line. Check before applying"
  defp seal_label(:clear), do: "Figure: a bare line. Passes inspection"
end
