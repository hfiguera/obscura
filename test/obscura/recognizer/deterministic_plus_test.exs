defmodule Obscura.Recognizer.DeterministicPlusTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.Profile

  test "phone recognizer detects generated short parenthesized phone numbers" do
    assert {:ok, [result]} =
             Obscura.analyze("Please call me at (96) 627-277",
               entities: [:phone],
               profile: :regex_only
             )

    assert result.entity == :phone
    assert result.text == "(96) 627-277"
    assert result.source_entity == "PHONE_NUMBER"
  end

  test "phone recognizer detects generated spaced and extension formats" do
    examples = [
      "(07) 5331 0577",
      "027 896 92 86",
      "21 212 133 2727",
      "001-420-335-7509x38548",
      "+1-944-435-4352x04732",
      "986.291.2294x751",
      "69 987 88 37"
    ]

    for phone <- examples do
      assert {:ok, [result]} =
               Obscura.analyze("Call #{phone}",
                 entities: [:phone],
                 profile: :regex_only
               )

      assert result.entity == :phone
      assert result.text == phone
    end
  end

  test "structured recognizers reject invalid parser/checksum-style candidates" do
    assert {:ok, []} = Obscura.analyze("Call 111-111-1111", entities: [:phone])
    assert {:ok, []} = Obscura.analyze("Email jane@-example.com", entities: [:email])
    assert {:ok, []} = Obscura.analyze("Visit https://example.invalid-", entities: [:url])
    assert {:ok, []} = Obscura.analyze("Domain -example.com", entities: [:domain])
  end

  test "phone recognizer supports optional parser-backed validation hooks" do
    validator = fn
      "202-555-0188", _opts -> {:ok, %{validation: :test_parser, region: :us}}
      _value, _opts -> {:error, :rejected_by_test_parser}
    end

    assert {:ok, [phone]} =
             Obscura.analyze("Call 202-555-0188",
               entities: [:phone],
               phone_validator: validator
             )

    assert phone.metadata.validation == :test_parser
    assert phone.metadata.region == :us

    assert {:ok, []} =
             Obscura.analyze("Call 303-555-0100",
               entities: [:phone],
               phone_validator: validator
             )
  end

  test "optional ex_phone_number parser improves Presidio international phone recall" do
    examples = [
      {"My Israeli number is 09-7625400", ["09-7625400"]},
      {"_: +55 11 98456 5666", ["+55 11 98456 5666"]},
      {"My Japanese number is 090-1234-5678", ["090-1234-5678"]},
      {"My CN number is 13812345678", ["13812345678"]},
      {"My US number is (415) 555-0132, and my international one is +44 (20) 7123 4567",
       ["(415) 555-0132", "+44 (20) 7123 4567"]},
      {"My US number is (415) 555-0132, and my international one is +91 4155550132",
       ["(415) 555-0132", "+91 4155550132"]},
      {"My US number is (415) 555-0132, and my international one is +49 30 1234567",
       ["(415) 555-0132", "+49 30 1234567"]}
    ]

    baseline_results =
      Enum.map(examples, fn {text, expected} ->
        {:ok, results} = Obscura.analyze(text, entities: [:phone], profile: :regex_only)
        {expected, Enum.map(results, & &1.text)}
      end)

    parser_results =
      Enum.map(examples, fn {text, expected} ->
        {:ok, results} =
          Obscura.analyze(text,
            entities: [:phone],
            profile: :regex_only,
            phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator
          )

        {expected, Enum.map(results, & &1.text)}
      end)

    expected = Enum.flat_map(examples, fn {_text, expected} -> expected end)
    baseline_found = Enum.flat_map(baseline_results, fn {_expected, found} -> found end)
    parser_found = Enum.flat_map(parser_results, fn {_expected, found} -> found end)

    assert exact_match_count(baseline_results) == 3
    assert baseline_found -- expected == ["(20) 7123 4567", "4155550132"]
    assert exact_match_count(parser_results) == 10
    assert parser_found == expected
  end

  test "optional ex_phone_number parser rejects invalid numeric candidates" do
    assert {:ok, []} =
             Obscura.analyze("Reference 2026-06-07 is not a phone number.",
               entities: [:phone],
               profile: :regex_only,
               phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator
             )
  end

  test "parser-backed phone filtering requires evidence for national candidates" do
    validator = fn _value, _opts -> {:ok, %{validation: :parser}} end

    assert {:ok, []} =
             Obscura.analyze("Reference 09-7625400 should not be accepted without context.",
               entities: [:phone],
               profile: :regex_only,
               phone_validator: validator
             )

    assert {:ok, [plus_prefixed]} =
             Obscura.analyze("Reference +55 11 98456 5666 is international.",
               entities: [:phone],
               profile: :regex_only,
               phone_validator: validator
             )

    assert plus_prefixed.metadata.phone_parser_acceptance == :plus_prefixed

    assert {:ok, [contextual]} =
             Obscura.analyze("My telephone number is 09-7625400.",
               entities: [:phone],
               profile: :regex_only,
               phone_validator: validator
             )

    assert contextual.metadata.phone_parser_acceptance == :context

    assert {:ok, []} =
             Obscura.analyze("Call 123-456-7890.",
               entities: [:phone],
               profile: :regex_only,
               phone_validator: validator
             )
  end

  test "domain recognizer preserves generated posted-photo URL domain spans" do
    text = "Just posted a photo http://www.DialForum.co.uk/"

    assert {:ok, results} =
             Obscura.analyze(text,
               entities: [:domain],
               profile: :regex_only
             )

    assert [result] = results
    assert result.entity == :domain
    assert result.text == "http://www.DialForum.co.uk/"
    assert result.source_entity == "DOMAIN_NAME"
  end

  test "deterministic_plus detects generated billing-address people, address parts, and city" do
    text = """
    billing address: tracy sukhorukova
        23 8 wressle road suite 771
       polapit tamar
        nan
        77058
    """

    assert {:ok, results} = Obscura.analyze(text, profile: :deterministic_plus)

    assert span(results, :person, "tracy sukhorukova")
    assert span(results, :street_address, "23")
    assert span(results, :street_address, "8 wressle road")
    assert span(results, :street_address, "suite 771")
    assert span(results, :street_address, "nan")
    assert span(results, :street_address, "77058")
    assert span(results, :location, "polapit tamar")
  end

  test "deterministic_plus detects generated inline address names and city" do
    text = "john had given shamhan his address: 46 velký průhon 426, opocnice"

    assert {:ok, results} = Obscura.analyze(text, profile: :deterministic_plus)

    assert span(results, :person, "john")
    assert span(results, :person, "shamhan")
    assert span(results, :street_address, "46")
    assert span(results, :street_address, "velký průhon 426")
    assert span(results, :location, "opocnice")
  end

  test "deterministic_plus detects titled names and travel destinations" do
    assert {:ok, name_results} =
             Obscura.analyze("Please route this to ms. Wijtze", profile: :deterministic_plus)

    assert span(name_results, :person, "Wijtze")

    assert {:ok, location_results} =
             Obscura.analyze("We returned to Blaketown by helicopter.",
               profile: :deterministic_plus
             )

    assert span(location_results, :location, "Blaketown")
  end

  test "deterministic_plus detects broader high-confidence generated contexts" do
    text = "Shelby Araujo lives at 87 Jakobi 69, Laane"

    assert {:ok, results} = Obscura.analyze(text, profile: :deterministic_plus)

    assert span(results, :person, "Shelby Araujo")
    assert span(results, :street_address, "87")
    assert span(results, :street_address, "Jakobi 69")
    assert span(results, :location, "Laane")

    assert {:ok, name_results} =
             Obscura.analyze("My name is Patricia Jeknić but everyone calls me Lauren",
               profile: :deterministic_plus
             )

    assert span(name_results, :person, "Patricia Jeknić")
    assert span(name_results, :person, "Lauren")

    assert {:ok, zip_results} = Obscura.analyze("ZIP: 11164", profile: :deterministic_plus)
    assert span(zip_results, :street_address, "11164")
  end

  test "deterministic_plus detects labeled contact-card addresses conservatively" do
    text = """
    Name: Rachel Green
    Phone: 202-555-0188
    Address: 123 Main Street
    Apt. 4B
    Denver, CO 80202
    """

    assert {:ok, results} = Obscura.analyze(text, profile: :deterministic_plus)

    assert span(results, :street_address, "123 Main Street\nApt. 4B\nDenver, CO 80202")

    assert {:ok, []} =
             Obscura.analyze("The main street project starts tomorrow.",
               entities: [:street_address],
               profile: :deterministic_plus
             )
  end

  test "deterministic_plus detects generated dates, titles, and location contexts" do
    assert {:ok, event_results} =
             Obscura.analyze("When: 1998-06-28 14:48:14\nWhere: Kouklia Country Club.",
               profile: :deterministic_plus
             )

    assert span(event_results, :date_time, "1998-06-28 14:48:14")
    assert span(event_results, :location, "Kouklia")

    assert {:ok, title_results} =
             Obscura.analyze("Dr. Nielsen grew up in Ústí nad Labem 2.",
               profile: :deterministic_plus
             )

    assert span(title_results, :title, "Dr.")
    assert span(title_results, :person, "Nielsen")
    assert span(title_results, :location, "Ústí nad Labem 2")
  end

  test "deterministic_plus detects Presidio-style date formats conservatively" do
    examples = [
      "She was born on 12/27/1986.",
      "It's like that since 12/1/1977",
      "Recorded at 2026-06-07T14:30:00Z.",
      "Reviewed on 2026/06/07.",
      "Reviewed on 07.06.2026.",
      "Reviewed on 07-JUN-2026."
    ]

    for text <- examples do
      assert {:ok, [_date | _]} =
               Obscura.analyze(text,
                 entities: [:date_time],
                 profile: :deterministic_plus
               )
    end

    assert {:ok, []} =
             Obscura.analyze("The reference number is 12/34.",
               entities: [:date_time],
               profile: :deterministic_plus
             )
  end

  test "hybrid_gliner_ortex enables structured deterministic spans but not deterministic person or location" do
    assert {:ok, structured_results} =
             Obscura.analyze("Reviewed on 2026-06-07.\nAddress: 123 Main Street",
               entities: [:date_time, :street_address],
               profile: :hybrid_gliner_ortex
             )

    assert span(structured_results, :date_time, "2026-06-07")
    assert span(structured_results, :street_address, "123 Main Street")

    assert {:ok, []} =
             Obscura.analyze("Please route this to ms. Wijtze",
               entities: [:person],
               profile: :hybrid_gliner_ortex
             )

    assert {:ok, []} =
             Obscura.analyze("When: 1998-06-28 14:48:14\nWhere: Kouklia Country Club.",
               entities: [:location],
               profile: :hybrid_gliner_ortex
             )
  end

  test "deterministic_plus detects explicit generated address contexts" do
    examples = [
      {"I need to add my addresses, here they are: 63 30 N. Stadion\nULLINISH\n, nan\n 40839, and 75 Auerstrasse 12 Apt. 974 Lyss São Tomé",
       ["63 30 N. Stadion\nULLINISH\n, nan\n 40839", "75 Auerstrasse 12 Apt. 974 Lyss São Tomé"]},
      {"As promised, here's Arne's address:\n\n06 Reyes Católicos 17\nSaarjärve, JN 91851",
       ["06 Reyes Católicos 17\nSaarjärve, JN 91851"]},
      {"Please return to 39 79 Argyll Road\nNoorderwijk\n, VAN\n Portugal 76970 in case of an issue.",
       ["39 79 Argyll Road\nNoorderwijk\n, VAN\n Portugal 76970"]},
      {"I once lived in 95 Bem rkp. 97. Suite 446, Poznań, Bolivia 28327. I now live in the corner of Kapelaniestraat 88 and Whittaker Street",
       [
         "95 Bem rkp. 97. Suite 446, Poznań, Bolivia 28327",
         "the corner of Kapelaniestraat 88 and Whittaker Street"
       ]},
      {"How do I change my address to 16 48 rue Descartes, Monte Gil, Canada for post mail?",
       ["16 48 rue Descartes, Monte Gil, Canada"]}
    ]

    for {text, expected_spans} <- examples do
      assert {:ok, results} =
               Obscura.analyze(text,
                 entities: [:street_address],
                 profile: :deterministic_plus
               )

      for expected <- expected_spans do
        assert span(results, :street_address, expected)
      end
    end
  end

  test "deterministic_plus detects contact-block address and person contexts" do
    text = """
    Taylor Barabás
    Areavibes Inc
    27 2279 President St
    Gleniti
    , nan
     Canada 32586
    Mobile: 041-412-293
    """

    assert {:ok, results} = Obscura.analyze(text, profile: :deterministic_plus)

    assert span(results, :person, "Taylor Barabás")
    assert span(results, :street_address, "27 2279 President St\nGleniti\n, nan\n Canada 32586")
  end

  test "deterministic_plus detects narrow generated person and location contexts" do
    examples = [
      {"I'm so jealous! said Honoré to James", [:person], ["Honoré", "James"]},
      {"What's your last name? Krylova", [:person], ["Krylova"]},
      {"Sometimes people call me Roland", [:person], ["Roland"]},
      {"She was born on 12/27/1986. Her maiden name is Vestergaard", [:person], ["Vestergaard"]},
      {"It was a done thing between him and Sumaya's kid; and everybody thought so.", [:person],
       ["Sumaya"]},
      {"Delvis spent a year at Weight Watchers as the assistant to Douglas Lind.", [:person],
       ["Delvis", "Douglas Lind"]},
      {"Morishita began writing as a teenager.", [:person], ["Morishita"]},
      {"The Princess Royal arrived at Nugeri this morning from Niger.", [:location],
       ["Nugeri", "Niger"]},
      {"We moved here from Küsnacht", [:location], ["Küsnacht"]},
      {"Morishita studied journalism at the University of Zafferana Etnea.", [:location],
       ["Zafferana Etnea"]}
    ]

    for {text, entities, expected_spans} <- examples do
      assert {:ok, results} =
               Obscura.analyze(text, entities: entities, profile: :deterministic_plus)

      for expected <- expected_spans do
        assert Enum.any?(results, &(&1.text == expected))
      end
    end
  end

  test "deterministic_plus keeps posted-photo URL as domain without URL duplicate" do
    text = "Just posted a photo http://www.DialForum.co.uk/"

    assert {:ok, default_results} = Obscura.analyze(text, profile: :deterministic_plus)
    assert span(default_results, :domain, "http://www.DialForum.co.uk/")
    refute span(default_results, :url, "http://www.DialForum.co.uk/")

    assert {:ok, url_results} =
             Obscura.analyze(text,
               entities: [:url],
               profile: :deterministic_plus
             )

    assert span(url_results, :url, "http://www.DialForum.co.uk/")
  end

  test "deterministic_plus avoids obvious false positives" do
    assert {:ok, email_results} =
             Obscura.analyze("What's your email? LeaVLind@superrito.com",
               entities: [:email, :domain],
               profile: :deterministic_plus
             )

    assert span(email_results, :email, "LeaVLind@superrito.com")
    refute Enum.any?(email_results, &(&1.entity == :domain))

    assert {:ok, by_results} =
             Obscura.analyze("This was written by a committee in the 10th year of the program.",
               entities: [:person, :location],
               profile: :deterministic_plus
             )

    assert by_results == []
  end

  test "deterministic_plus profile only claims entities with local deterministic recognizers" do
    assert Profile.supported_entities(:deterministic_plus) == [
             :credit_card,
             :date_time,
             :domain,
             :email,
             :iban,
             :ip_address,
             :location,
             :person,
             :phone,
             :street_address,
             :title,
             :url,
             :us_ssn
           ]
  end

  defp span(results, entity, text) do
    Enum.find(results, &(&1.entity == entity and &1.text == text))
  end

  defp exact_match_count(results) do
    Enum.reduce(results, 0, fn {expected, found}, count ->
      count + Enum.count(found, &(&1 in expected))
    end)
  end
end
