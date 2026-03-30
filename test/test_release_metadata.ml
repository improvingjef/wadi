open Test_support

let cases =
  [
    ( "loads release metadata and derives canonical release names",
      (fun () ->
        let metadata =
          expect_ok
            (Release_metadata.load
               (Filename.concat (Sys.getcwd ()) "release/metadata.sh"))
        in
        assert_string_equal "oasis" metadata.package_name
          "release metadata should preserve the package name";
        assert_string_equal "v0.1.0"
          (Release_metadata.release_tag metadata)
          "release metadata should derive the release tag";
        assert_string_equal "oasis-0.1.0-source.tar.gz"
          (Release_metadata.source_archive_name metadata)
          "release metadata should derive the source archive name";
        assert_string_equal
          "https://github.com/jef/oasis/releases/download/v0.1.0/oasis-0.1.0-source.tar.gz"
          (Release_metadata.source_archive_url metadata)
          "release metadata should derive the source archive URL";
        assert_string_equal "https://github.com/jef/homebrew-oasis"
          (Release_metadata.homebrew_tap_clone_url metadata)
          "release metadata should derive the default tap clone URL") );
    ( "rejects release metadata files that omit required fields",
      (fun () ->
        with_temp_dir "oasis-release-metadata" (fun workspace ->
            let metadata_path = Filename.concat workspace "metadata.sh" in
            Fs.write_file metadata_path
              {|
#!/bin/sh
OASIS_PACKAGE_NAME='oasis'
OASIS_RELEASE_VERSION='0.1.0'
|};
            let error = expect_error (Release_metadata.load metadata_path) in
            assert_string_contains
              ~needle:"missing required metadata OASIS_FORMULA_CLASS" error
              "release metadata loading should fail on missing canonical fields")) );
  ]
