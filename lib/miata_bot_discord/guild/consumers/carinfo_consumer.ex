defmodule MiataBotDiscord.Guild.CarinfoConsumer do
  @moduledoc """
  Processes commands from users
  """

  use GenStage
  require Logger
  import MiataBotDiscord.Guild.Registry, only: [via: 2]
  alias MiataBotDiscord.Guild.{EventDispatcher, Responder}
  alias MiataBotDiscord.GuildCache

  alias Nostrum.Struct.{Message, Embed}

  @help_message %Embed{}
                |> Embed.put_title("Available commands")
                |> Embed.put_field("carinfo", """
                Shows the author's carinfo
                """)
                |> Embed.put_field("carinfo me", """
                Shows *your* carinfo
                """)
                |> Embed.put_field("carinfo get <user>", """
                Shows a users carinfo
                """)
                |> Embed.put_field("carinfo update title", """
                Sets the author's carinfo title
                """)
                |> Embed.put_field("carinfo update image", """
                Updates the author's carinfo from an attached photo
                """)
                |> Embed.put_field("carinfo update year <year>", """
                Sets the author's carinfo year
                """)
                |> Embed.put_field("carinfo update color code <color>", """
                Sets the author's carinfo color code
                """)
                |> Embed.put_field("carinfo update mileage <mileage>", """
                Sets the author's carinfo mileage (add `km` to convert)
                """)
                |> Embed.put_field("carinfo update wheels <wheel name>", """
                Sets the author's carinfo wheels
                """)
                |> Embed.put_field("carinfo update tires <tire name>", """
                Sets the author's carinfo tire
                """)
                |> Embed.put_field("carinfo update instagram <handle>", """
                Sets the author's instagram handle
                """)

  @doc false
  def start_link({guild, config, current_user}) do
    GenStage.start_link(__MODULE__, {guild, config, current_user}, name: via(guild, __MODULE__))
  end

  @impl GenStage
  def init({guild, config, current_user}) do
    {:producer_consumer, %{guild: guild, current_user: current_user, config: config},
     subscribe_to: [via(guild, EventDispatcher)]}
  end

  @impl GenStage
  def handle_events(events, _from, %{current_user: %{id: current_user_id}} = state) do
    {actions, state} =
      Enum.reduce(events, {[], state}, fn
        # Ignore messages from self
        {:MESSAGE_CREATE, %{author: %{id: author_id}}}, {actions, state}
        when author_id == current_user_id ->
          {actions, state}

        {:GUILD_MEMBER_ADD, new}, {actions, state} ->
          handle_member_add(new, {actions, state})

        {:MESSAGE_CREATE, message}, {actions, state} ->
          handle_message(message, {actions, state})

        _, {actions, state} ->
          {actions, state}
      end)

    {:noreply, actions, state}
  end

  def handle_member_add(new, {actions, state}) do
    _ = fetch_or_create_build(new.user)
    {actions, state}
  end

  # this blocks all other patterns from matching in the verification channel. IDK what to do about it
  # def handle_message(%Message{channel_id: verification_channel_id} = message, {actions, %{config: %{verification_channel_id: verification_channel_id}} = state}) do
  #   case message.attachments do
  #     [%{url: url} | _rest] ->
  #       year = extract_year(message.content)
  #       params = %{attachment_url: url, discord_user_id: message.author.id, year: year}
  #       handle_update_build(verification_channel_id, message.author, params, {actions, state})

  #     _ ->
  #       {actions, state}
  #   end
  # end

  def handle_message(%Message{channel_id: channel_id, content: "$carinfo help"}, {actions, state}) do
    {actions ++ [{:create_message!, [channel_id, [embed: @help_message]]}], state}
  end

  def handle_message(%Message{channel_id: channel_id, content: "$carinfo"}, {actions, state}) do
    {actions ++ [{:create_message!, [channel_id, [embed: @help_message]]}], state}
  end

  def handle_message(
        %Message{channel_id: channel_id, author: author, content: "$carinfo me" <> _},
        {actions, state}
      ) do
    case fetch_or_create_build(author) do
      {:ok, build} ->
        embed = embed_from_info(author, build)
        {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}

      {:error, _} ->
        {actions ++ [{:create_message!, [channel_id, "Could not find build. ping cone"]}], state}
    end
  end

  def handle_message(
        %Message{channel_id: channel_id, content: "$carinfo get" <> user} = message,
        {actions, state}
      ) do
    with {:ok, user} <- get_user(message),
         {:ok, build} <- fetch_or_create_build(user),
         embed <- embed_from_info(user, build) do
      {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}
    else
      {:error, _} ->
        {actions ++ [{:create_message!, [channel_id, "Could not find user: #{user}"]}], state}
    end
  end

  def handle_message(
        %Message{
          content: "$carinfo update image" <> _,
          channel_id: channel_id,
          author: author,
          attachments: [attachment | _]
        },
        {actions, state}
      ) do
    params = %{attachment_url: attachment.url, discord_user_id: author.id}
    handle_update_image(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update photo" <> _,
          channel_id: channel_id,
          author: author,
          attachments: [attachment | _]
        },
        {actions, state}
      ) do
    params = %{attachment_url: attachment.url, discord_user_id: author.id}
    handle_update_image(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update year " <> year,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{year: year, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update vin " <> vin,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{vin: vin, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update mileage " <> mileage,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{mileage: mileage, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update color code " <> color,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{color: color, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update title " <> title,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{description: title, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update description " <> description,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{description: description, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update wheels " <> wheels,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{wheels: wheels, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update tires " <> tires,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{tires: tires, discord_user_id: author.id}
    handle_update_build(channel_id, author, params, {actions, state})
  end

  def handle_message(
        %Message{
          content: "$carinfo update instagram " <> instagram_handle,
          channel_id: channel_id,
          author: author
        },
        {actions, state}
      ) do
    params = %{instagram_handle: instagram_handle, discord_user_id: author.id}
    handle_update_user(channel_id, author, params, {actions, state})
  end

  def handle_message(_message, {actions, state}) do
    {actions, state}
  end

  def handle_update_user(channel_id, author, params, {actions, state}) do
    case MiataBot.Partpicker.update_user(author.id, params) do
      {:ok, _user} ->
        embed = fetch_or_create_build(author)
        {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}

      {:error, reason} ->
        embed =
          %Embed{}
          |> Embed.put_title("Error updating info")
          |> Embed.put_color(0xFF0000)
          |> put_errors(reason)

        {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}
    end
  end

  def handle_update_image(channel_id, author, params, {actions, state}) do
    case do_update_image(author, params) do
      {:ok, embed} ->
        {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}
    end
  end

  def handle_update_build(channel_id, author, params, {actions, state}) do
    case do_update_build(author, params) do
      {:ok, embed} ->
        {actions ++ [{:create_message!, [channel_id, [embed: embed]]}], state}
    end
  end

  defp do_update_build(author, params) do
    with {:ok, info} <- fetch_or_create_build(author),
         {:ok, info} <- update_build(author, info, params),
         embed <- embed_from_info(author, info) do
      {:ok, embed}
    else
      {:error, reason} ->
        embed =
          %Embed{}
          |> Embed.put_title("Error updating info")
          |> Embed.put_color(0xFF0000)
          |> put_errors(reason)

        {:ok, embed}

      unknown ->
        raise "unknown error #{inspect(unknown)}"
    end
  end

  def do_update_image(author, params) do
    with {:ok, info} <- fetch_or_create_build(author),
         {:ok, info} <- update_image(author, info, params),
         embed <- embed_from_info(author, info) do
      {:ok, embed}
    else
      {:error, reason} ->
        embed =
          %Embed{}
          |> Embed.put_title("Error updating info")
          |> Embed.put_color(0xFF0000)
          |> put_errors(reason)

        {:ok, embed}

      unknown ->
        raise "unknown error #{inspect(unknown)}"
    end
  end

  def put_errors(embed, error) do
    Enum.reduce(error, embed, fn {key, msg}, embed ->
      Embed.put_field(embed, to_string(key), Enum.join(msg, " "))
    end)
  end

  def fetch_or_create_build(author) do
    case MiataBot.Partpicker.builds(author.id) do
      {:ok, []} -> create_build(author)
      {:error, %{"error" => ["not found"]}} -> create_build(author)
      {:ok, [info | _]} -> {:ok, info}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_build(author, info, params) do
    MiataBot.Partpicker.update_build(author.id, info.uid, params)
  end

  def create_build(author) do
    MiataBot.Partpicker.create_build(author.id, %{discord_user_id: author.id})
  end

  def update_image(author, info, params) do
    MiataBot.Partpicker.update_banner(author.id, info.uid, params)
  end

  def embed_from_info(author, info) do
    %Embed{}
    |> Embed.put_title("#{author.username}'s Miata")
    |> Embed.put_url("https://miatapartpicker.gay/car/#{info.uid}")
    |> Embed.put_description(info.description)
    |> maybe_add_year(info)
    |> maybe_add_color(info)
    |> maybe_add_image(info)
    |> maybe_add_wheels(info)
    |> maybe_add_tires(info)
    |> maybe_add_mileage(info)
    |> maybe_add_vin(info)
    |> maybe_add_instagram(info)
  end

  def maybe_add_year(embed, %{year: nil}), do: embed
  def maybe_add_year(embed, %{year: year}), do: Embed.put_field(embed, "Year", year, true)

  def maybe_add_image(embed, %{banner_photo_url: nil}), do: embed
  def maybe_add_image(embed, %{banner_photo_url: url}), do: Embed.put_image(embed, url)

  def maybe_add_wheels(embed, %{wheels: nil}), do: embed

  def maybe_add_wheels(embed, %{wheels: wheels}),
    do: Embed.put_field(embed, "Wheels", wheels, true)

  def maybe_add_tires(embed, %{tires: nil}), do: embed
  def maybe_add_tires(embed, %{tires: tires}), do: Embed.put_field(embed, "Tires", tires, true)

  def maybe_add_vin(embed, %{vin: nil}), do: embed
  def maybe_add_vin(embed, %{vin: vin}), do: Embed.put_field(embed, "VIN", vin, true)

  def maybe_add_mileage(embed, %{mileage: nil}), do: embed

  def maybe_add_mileage(embed, %{mileage: mileage, user: %{prefered_unit: :miles}}),
    do: Embed.put_field(embed, "Mileage", "#{mileage} miles", true)

  def maybe_add_mileage(embed, %{mileage: mileage, user: %{prefered_unit: :km}}),
    do: Embed.put_field(embed, "Mileage", "#{mileage} km", true)

  def maybe_add_instagram(embed, %{user: %{instagram_handle: nil}}), do: embed

  def maybe_add_instagram(embed, %{user: %{instagram_handle: "@" <> handle}}),
    do: Embed.put_field(embed, "Instagram", "https://instagram.com/#{handle}")

  def maybe_add_instagram(embed, %{user: %{instagram_handle: handle}}),
    do: Embed.put_field(embed, "Instagram", "https://instagram.com/#{handle}")

  def maybe_add_color(embed, %{color: nil}), do: embed

  def maybe_add_color(embed, %{color: color}) do
    embed = Embed.put_field(embed, "Color", color, true)
    color = String.downcase(color)

    cond do
      String.contains?(color, "red") -> Embed.put_color(embed, 0xD11A06)
      String.contains?(color, "green") -> Embed.put_color(embed, 0x00FF00)
      String.contains?(color, "blue") -> Embed.put_color(embed, 0x0000FF)
      String.contains?(color, "white") -> Embed.put_color(embed, 0xFFFFFF)
      String.contains?(color, "black") -> Embed.put_color(embed, 0x000000)
      true -> embed
    end
  end

  defp get_user(%Message{mentions: [user | _]}) do
    {:ok, user}
  end

  defp get_user(%Message{content: "$carinfo get" <> identifier} = message) do
    case String.trim(identifier) do
      "me" ->
        {:ok, message.author}

      "" ->
        {:ok, message.author}

      str ->
        case Snowflake.cast(str) do
          {:ok, snowflake} ->
            Logger.info("using snowflake: #{str}")
            Responder.execute_action(message.guild_id, {:get_user, [snowflake]})

          :error ->
            Logger.info("using nick: #{str}")
            get_user_by_nick(str, message)
        end
    end
  end

  defp get_user_by_nick(nick, %Message{guild_id: guild_id} = _message) do
    Logger.info("looking up by nick: #{nick}")

    maybe_member =
      Enum.find(GuildCache.list_guild_members(guild_id), fn
        {_id, %Nostrum.Struct.Guild.Member{nick: ^nick}} ->
          true

        {_id, %Nostrum.Struct.Guild.Member{user: %{username: ^nick}}} ->
          true

        {_id, %Nostrum.Struct.Guild.Member{} = _member} ->
          # Logger.info("not match: #{inspect(member)}")
          false
      end)

    case maybe_member do
      {id, _member} ->
        Responder.execute_action(guild_id, {:get_user, [id]})

      nil ->
        {:error, "unable to match: #{nick}"}
    end
  end
end
