defmodule LureWeb.CheckLiveTest do
  use LureWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @scam """
  Data Entry Clerk - Work From Home. Earn $900 per week, no experience needed!
  Interview via Telegram with our hiring manager. Before training you must pay a $50 fee for
  your starter kit. Email recruiter.jobs@gmail.com with your bank account details to get paid.
  """

  test "the page offers a box to paste into and example ads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#ad-form")
    assert has_element?(view, "#ad-text")
    assert has_element?(view, "#sample-0")
    assert has_element?(view, "#how")
  end

  test "too little text asks for the whole ad", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> form("#ad-form", ad: %{text: "hiring now"}) |> render_submit()
    assert has_element?(view, "#error")
    refute has_element?(view, "#result")
  end

  test "an obvious scam gets a verdict, its red flags and the marked-up text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> form("#ad-form", ad: %{text: @scam}) |> render_submit()
    render_async(view, 20_000)
    assert has_element?(view, "#result")
    assert has_element?(view, "#flags li")
    assert has_element?(view, "#marked .f-span")
  end

  test "an example ad is checked in one click", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#sample-0") |> render_click()
    render_async(view, 20_000)
    assert has_element?(view, "#result")
  end

  test "the page can be framed by Hugging Face", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert get_resp_header(conn, "x-frame-options") == []
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'self' https://huggingface.co"
  end
end
