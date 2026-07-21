%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "fixtures/"],
        excluded: ["_build/", "deps/"]
      },
      plugins: [{ExSlop, []}]
    }
  ]
}
