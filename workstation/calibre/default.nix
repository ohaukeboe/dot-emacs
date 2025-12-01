{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  pushToRMScript = pkgs.writeShellScript "push-to-rm" ''
    #!/bin/bash
    rmapi put --coverpage=1 "$1"
  '';

  calibreDir = ".config/calibre";
  pluginsDir = "${calibreDir}/plugins";
in
{
  home.packages = with pkgs; [
    calibre
    rmapi
  ];

  home.file = {
    "${calibreDir}/conversion" = {
      source = ./calibre-config/conversion;
      force = true;
    };
    "${calibreDir}/global.py.json" = {
      source = ./calibre-config/global.py.json;
      force = true;
    };
    "${calibreDir}/gui.json" = {
      source = ./calibre-config/gui.json;
      force = true;
    };
    "${calibreDir}/gui.py.json" = {
      source = ./calibre-config/gui.py.json;
      force = true;
    };

    "${calibreDir}/dynamic.pickle.json" = {
      text = builtins.toJSON {
        "welcome_wizard_was_run" = true;
      };
      force = true;
    };

    "${calibreDir}/customize.py.json" = {
      text = builtins.toJSON {
        filetype_mapping = { };
        plugin_customization = { };
        plugins = {
          "Open With" = "${config.home.homeDirectory}/${pluginsDir}/Open With.zip";
          "DeDRM" = inputs.calibre-plugins.packages.${pkgs.stdenv.hostPlatform.system}.dedrm-plugin;
          "ACSM Input" =
            inputs.calibre-plugins.packages.${pkgs.stdenv.hostPlatform.system}.acsm-calibre-plugin;
        };
      };
      force = true;
    };

    "${pluginsDir}/Open With.zip" = {
      source = ./calibre-config/plugins + "/Open With.zip";
      force = true;
    };
    "${pluginsDir}/DeACSM/account" = {
      source = ../../secrets/deacsm;
      force = true;
    };

    "${pluginsDir}/Open With.json" = {
      text = builtins.toJSON {
        OpenWithMenus = {
          Menus = [
            {
              active = true;
              appArgs = "";
              appPath = "firefox";
              format = "EPUB";
              image = "owp_firefox.png";
              menuText = "EPUBReader (EPUB)";
              subMenu = "";
            }
            {
              active = true;
              appArgs = "";
              appPath = "${pushToRMScript}";
              format = "EPUB";
              image = "";
              menuText = "reMarkable (EPUB)";
              subMenu = "";
            }
            {
              active = true;
              appArgs = "";
              appPath = "${pushToRMScript}";
              format = "PDF";
              image = "";
              menuText = "reMarkable (PDF)";
              subMenu = "";
            }
          ];
          UrlColWidth = 144;
        };
      };
      force = true;
    };

    "${pluginsDir}/global.py.json" = {
      text = builtins.toJSON {
        add_formats_to_existing = false;
        case_sensitive = false;
        check_for_dupes_on_ctl = false;
        database_path = "${config.home.homeDirectory}/library1.db";
        filename_pattern = "(?P<title>.+) - (?P<author>[^_]+)";
        input_format_order = [
          "EPUB"
          "AZW3"
          "MOBI"
          "LIT"
          "PRC"
          "FB2"
          "HTML"
          "HTM"
          "XHTM"
          "SHTML"
          "XHTML"
          "ZIP"
          "DOCX"
          "ODT"
          "RTF"
          "PDF"
          "TXT"
        ];
        installation_uuid = "5546391e-0253-4a9b-8df8-a0f85c6f6bb1";
        isbndb_com_key = "";
        language = "en";
        library_path = "${config.home.homeDirectory}/Nextcloud/calibre_library";
        limit_search_columns = false;
        limit_search_columns_to = [
          "title"
          "authors"
          "tags"
          "series"
          "publisher"
        ];
        manage_device_metadata = "manual";
        mark_new_books = false;
        migrated = false;
        network_timeout = 5;
        new_book_tags = [ ];
        numeric_collation = false;
        output_format = "epub";
        read_file_metadata = true;
        saved_searches = { };
        swap_author_names = false;
        use_primary_find_in_search = true;
        user_categories = { };
        worker_process_priority = "normal";
      };
    };
  };
}
