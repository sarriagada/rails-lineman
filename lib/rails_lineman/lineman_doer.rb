require 'pathname'
require 'fileutils'

module RailsLineman
  class LinemanDoer
    def initialize(config)
      @lineman_project_location = config.lineman_project_location
      @javascripts_source = File.join(@lineman_project_location, "dist", "js", ".")
      @javascripts_destination = Rails.root.join(config.javascripts_destination)
      @stylesheets_source = File.join(@lineman_project_location, "dist", "css", ".")
      @stylesheets_destination = Rails.root.join(config.stylesheets_destination)
      @tmp_dir = Rails.root.join(config.tmp_dir)
      @remove_lineman_assets_after_asset_pipeline_precompilation = config.remove_lineman_assets_after_asset_pipeline_precompilation
    end

    def build
      absolutify_lineman_path
      chdir @lineman_project_location do
        install_node_js_on_heroku
        run_npm_install
        run_lineman_build
        delete_node_js_from_heroku
      end
      ensure_directories_exist
      copy_javascripts
      add_javascripts_to_precompile_list
      copy_stylesheets
      add_stylesheets_to_precompile_list
    end

    def destroy
      return unless @remove_lineman_assets_after_asset_pipeline_precompilation
      delete_javascripts
      delete_stylesheets
      delete_tmp_dir
    end

  private

    def absolutify_lineman_path
      @lineman_project_location = Pathname.new(@lineman_project_location).realpath.to_s
    rescue => error
      puts <<-ERROR

        rails-lineman was not able to find your Lineman project at the path: `#{@lineman_project_location}`

        To configure the plugin to find your Lineman project, set one of these to its path:
          * An environment variable $LINEMAN_PROJECT_LOCATION
          * The config property `Rails.application.config.rails_lineman.lineman_project_location`

      ERROR
      raise error
    end

    def chdir(path)
      og_dir = Dir.pwd
      Dir.chdir(path)
      yield
      Dir.chdir(og_dir)
    end

    def install_node_js_on_heroku
      if heroku?
        puts "It looks like we're on heroku, so let's install Node.js"
        system <<-BASH
          node_version=$(curl --silent --get https://semver.io/node/resolve)
          node_url="http://s3pository.heroku.com/node/v$node_version/node-v$node_version-linux-x64.tar.gz"
          curl "$node_url" -s -o - | tar xzf - -C .
          mv node-v$node_version-linux-x64 heroku_node_install
          chmod +x heroku_node_install/bin/*
          export PATH="$PATH:$(pwd)/heroku_node_install/bin"
        BASH
        ENV['PATH'] += ":#{Dir.pwd}/heroku_node_install/bin"
      end
    end

    def heroku?
      ENV['DYNO'] && ENV['STACK']
    end

    def run_npm_install
      return if system "npm install"
      raise <<-ERROR

        rails-lineman failed while running `npm install` from the `#{@lineman_project_location}` directory.

        Make sure that you have Node.js installed on your system and that `npm` is on your PATH.

        You can download Node.js here: http://nodejs.org

      ERROR
    end

    def run_lineman_build
      return if system "lineman build"
      return if system "./node_modules/.bin/lineman build"

      raise <<-ERROR

        rails-lineman failed when trying to run `lineman build`.

        Attempted to execute `lineman` as if on your PATH, then directly from
        the npm binstub at `./node_modules/.bin/lineman`.

        Try again after installing lineman globally with `npm install -g lineman`

      ERROR
    end

    def delete_node_js_from_heroku
      system "rm -rf heroku_node_install" if heroku?
    end

    def ensure_directories_exist
      ([@javascripts_source, @javascripts_destination, @stylesheets_source, @stylesheets_destination]).each do |path|
        FileUtils.mkdir_p(path)
      end
    end

    def copy_javascripts
      FileUtils.cp_r(@javascripts_source, @javascripts_destination)
    end

    def add_javascripts_to_precompile_list
      Rails.application.config.assets.precompile += Dir.glob("#{@javascripts_destination}/**/*.js")
    end

    def copy_stylesheets
      FileUtils.cp_r(@stylesheets_source, @stylesheets_destination)
    end

    def add_stylesheets_to_precompile_list
      Rails.application.config.assets.precompile += Dir.glob("#{@stylesheets_destination}/**/*.css")
    end

    def delete_javascripts
      FileUtils.rm_rf(@javascripts_destination)
    end

    def delete_stylesheets
      FileUtils.rm_rf(@stylesheets_destination)
    end

    def delete_tmp_dir
      FileUtils.rm_rf(@tmp_dir)
    end

  end
end