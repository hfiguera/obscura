mk_span = fn text, entity, value, source_entity, metadata ->
  {byte_start, _length} = :binary.match(text, value)
  byte_end = byte_start + byte_size(value)
  {:ok, char_start} = Obscura.Eval.Offset.byte_to_char(text, byte_start)
  {:ok, char_end} = Obscura.Eval.Offset.byte_to_char(text, byte_end)

  %{
    entity: entity,
    byte_start: byte_start,
    byte_end: byte_end,
    char_start: char_start,
    char_end: char_end,
    value: value,
    source_entity: source_entity,
    score_range: nil,
    match_strategy: :exact,
    required: true,
    metadata: metadata
  }
end

mk_fixture = fn id, text, entities, expected_values, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "obscura:generated-small-accuracy-v1",
    source_license: nil,
    text: text,
    language: :en,
    entities: entities,
    expected:
      Enum.map(expected_values, fn {entity, value, source_entity, metadata} ->
        mk_span.(text, entity, value, source_entity, metadata)
      end),
    should_match: true,
    profile: :deterministic_plus,
    tags: [:obscura, :accuracy, :deterministic_plus | tags],
    notes: nil,
    metadata: %{dataset: :generated_small, sample_ids: [0, 1, 2, 4, 5, 7, 9, 20, 30, 31]}
  }
end

mk_negative = fn id, text, entities, tags ->
  %{
    id: id,
    kind: :analyzer,
    source: "obscura:generated-small-accuracy-v2",
    source_license: nil,
    text: text,
    language: :en,
    entities: entities,
    expected: [],
    should_match: false,
    profile: :deterministic_plus,
    tags: [:obscura, :accuracy, :deterministic_plus, :negative | tags],
    notes: nil,
    metadata: %{dataset: :generated_small, purpose: :false_positive_control}
  }
end

billing_address = """
billing address: tracy sukhorukova
    23 8 wressle road suite 771
   polapit tamar
    nan
    77058
"""

inline_address = "john had given shamhan his address: 46 velký průhon 426, opocnice"
travel_and_title = "Please route this to ms. Wijtze. We returned to Blaketown by helicopter."
short_phone = "Please call me at (96) 627-277"
lives_at = "Shelby Araujo lives at 87 Jakobi 69, Laane"
event = "When: 1998-06-28 14:48:14\nWhere: Kouklia Country Club."
named = "My name is Patricia Jeknić but everyone calls me Lauren"
titled_location = "Dr. Nielsen grew up in Ústí nad Labem 2."
phone_extensions = "Mobile: 041-412-293\nFax: 001-420-335-7509x38548"
posted_photo = "Just posted a photo http://www.DialForum.co.uk/"
zip_context = "ZIP: 11164"

[
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.billing_address",
    billing_address,
    [:person, :street_address, :location],
    [
      {:person, "tracy sukhorukova", "PERSON", %{pattern: :billing_address_name}},
      {:street_address, "23", "ADDRESS", %{pattern: :address_block}},
      {:street_address, "8 wressle road", "ADDRESS", %{pattern: :address_block}},
      {:street_address, "suite 771", "ADDRESS", %{pattern: :address_block}},
      {:location, "polapit tamar", "LOCATION", %{pattern: :address_city}},
      {:street_address, "nan", "ADDRESS", %{pattern: :address_block}},
      {:street_address, "77058", "ADDRESS", %{pattern: :address_block}}
    ],
    [:person, :street_address, :location, :billing_address]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.inline_address",
    inline_address,
    [:person, :street_address, :location],
    [
      {:person, "john", "PERSON", %{pattern: :account_address_subject}},
      {:person, "shamhan", "PERSON", %{pattern: :account_address_recipient}},
      {:street_address, "46", "ADDRESS", %{pattern: :inline_address}},
      {:street_address, "velký průhon 426", "ADDRESS", %{pattern: :inline_address}},
      {:location, "opocnice", "LOCATION", %{pattern: :inline_address_city}}
    ],
    [:person, :street_address, :location, :inline_address, :unicode]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.title_and_travel",
    travel_and_title,
    [:person, :location],
    [
      {:person, "Wijtze", "PERSON", %{pattern: :title_prefix}},
      {:location, "Blaketown", "LOCATION", %{pattern: :travel_destination}}
    ],
    [:person, :location, :title, :travel]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.short_phone",
    short_phone,
    [:phone],
    [
      {:phone, "(96) 627-277", "PHONE_NUMBER", %{pattern: :short_international_parens}}
    ],
    [:phone]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.lives_at",
    lives_at,
    [:person, :street_address, :location],
    [
      {:person, "Shelby Araujo", "PERSON", %{pattern: :lives_context}},
      {:street_address, "87", "ADDRESS", %{pattern: :lives_at_address}},
      {:street_address, "Jakobi 69", "ADDRESS", %{pattern: :lives_at_address}},
      {:location, "Laane", "LOCATION", %{pattern: :lives_at_city}}
    ],
    [:person, :street_address, :location, :lives_at]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.event_where",
    event,
    [:date_time, :location],
    [
      {:date_time, "1998-06-28 14:48:14", "DATE_TIME", %{pattern: :iso_timestamp}},
      {:location, "Kouklia", "LOCATION", %{pattern: :where_location}}
    ],
    [:date_time, :location, :event]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.my_name",
    named,
    [:person],
    [
      {:person, "Patricia Jeknić", "PERSON", %{pattern: :my_name}},
      {:person, "Lauren", "PERSON", %{pattern: :called_name}}
    ],
    [:person, :name_context]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.title_location",
    titled_location,
    [:title, :person, :location],
    [
      {:title, "Dr.", "TITLE", %{pattern: :honorific}},
      {:person, "Nielsen", "PERSON", %{pattern: :title_prefix}},
      {:location, "Ústí nad Labem 2", "LOCATION", %{pattern: :grew_up_in}}
    ],
    [:title, :person, :location, :unicode]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.email_without_domain_fp",
    "What's your email? LeaVLind@superrito.com",
    [:email, :domain],
    [
      {:email, "LeaVLind@superrito.com", "EMAIL_ADDRESS", %{pattern: :email}}
    ],
    [:email, :domain, :false_positive_control]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.phone_extensions",
    phone_extensions,
    [:phone],
    [
      {:phone, "041-412-293", "PHONE_NUMBER", %{pattern: :generated_short_dashed}},
      {:phone, "001-420-335-7509x38548", "PHONE_NUMBER",
       %{pattern: :international_trunk_extension}}
    ],
    [:phone, :extension]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.posted_photo_domain",
    posted_photo,
    [:domain],
    [
      {:domain, "http://www.DialForum.co.uk/", "DOMAIN_NAME", %{pattern: :posted_photo_url}}
    ],
    [:domain, :posted_photo]
  ),
  mk_fixture.(
    "obscura.accuracy.deterministic_plus.zip_context",
    zip_context,
    [:street_address],
    [
      {:street_address, "11164", "ADDRESS", %{pattern: :zip_context}}
    ],
    [:street_address, :zip_code]
  ),
  mk_negative.(
    "obscura.accuracy.deterministic_plus.no_context_address_or_person",
    "This was written by a committee in the 10th year of the program.",
    [:person, :location, :street_address],
    [:person, :location, :street_address]
  ),
  mk_negative.(
    "obscura.accuracy.deterministic_plus.lowercase_honorific_not_title",
    "Please route this to ms. Wijtze",
    [:title],
    [:title]
  )
]
