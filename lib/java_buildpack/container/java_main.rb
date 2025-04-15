# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2020 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/component/base_component'
require 'java_buildpack/container'
require 'java_buildpack/util/dash_case'
require 'java_buildpack/util/java_main_utils'
require 'java_buildpack/util/qualify_path'
require 'java_buildpack/util/spring_boot_utils'

module JavaBuildpack
  module Container

    # Encapsulates the detect, compile, and release functionality for applications running a simple Java +main()+
    # method. This isn't a _container_ in the traditional sense, but contains the functionality to manage the lifecycle
    # of Java +main()+ applications.
    class JavaMain < JavaBuildpack::Component::BaseComponent
      include JavaBuildpack::Util

      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        super(context)
        @spring_boot_utils = JavaBuildpack::Util::SpringBootUtils.new
      end

      # (see JavaBuildpack::Component::BaseComponent#detect)
      def detect
        main_class ? JavaMain.to_s.dash_case : nil
      end

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        return unless @spring_boot_utils.is?(@application)

        if @spring_boot_utils.thin?(@application)
          with_timing 'Caching Spring Boot Thin Launcher Dependencies', true do
            @spring_boot_utils.cache_thin_dependencies @droplet.java_home.root, @application.root, thin_root
          end
        end
        puts `echo "HELLO!!! ####################################"`

        puts `echo dropletroot "#{@droplet.root}"`
        puts `echo application root "#{@application.root}"`

        puts `echo droplet java_home root "#{@droplet.java_home.root}"`

        # puts `echo application "#{@application}"`
        puts `ls -al`
        puts `ls -al /tmp/`
        puts `pwd`
        puts `echo applicationname  "#{application_name}"`
        java = @droplet.java_home.root + 'bin/java'
        shell "cd #{@droplet.root} && zip -vr0 #{application_name}.jar . -x #{IGNORE_FILES}"
        puts `echo "Original jar:"  && ls -al #{@droplet.root}/#{application_name}.jar`
        # shell "cd #{@droplet.root} && rm -rf BOOT-INF/ META-INF/ org/" # do not remove cached and last_modified files
        shell "cd #{@droplet.root} && #{java} -Djarmode=tools -jar #{application_name}.jar extract"

        shell "cd #{@droplet.root} && rm #{application_name}.jar && mv #{application_name}/* ./ && rmdir #{application_name}"
        puts `echo "Extracted jar:"  && ls -al #{@droplet.root}/#{application_name}.jar`
        puts `echo /tmp/app`
        puts `ls -al /tmp/app/`
        puts `echo /tmp/app/lib`
        puts `ls -al /tmp/app/lib`



        # @droplet.additional_libraries.link_to(@spring_boot_utils.lib(@droplet))
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        # manifest_class_path.each { |path| @droplet.additional_libraries << path }
        if @spring_boot_utils.is?(@application)
          @droplet.environment_variables.add_environment_variable 'SERVER_PORT', '$PORT'

          if @spring_boot_utils.thin?(@application)
            @droplet.java_opts
                    .add_system_property('thin.offline', true)
                    .add_system_property('thin.root', thin_root)
          end
          ## COMMENT OUT BINDINGS CLASSPATH FILES FOR NOW TO FOCUS ON EXTRACT USE CASE
          ## WOULD NEED TO ADD BACK TO CONNECT TO A SERVICE
          ## WORKAROUND: IN APP POM.XML CAN INCLUDE THE JARS
          ## BUT IDEALLY - COME BACK AND CONFIGURE THIS PORPERLY FOR THE EXTRACTED USE CASE
        # else
        #   @droplet.additional_libraries.insert 0, @application.root
        end

        release_text()
      end

      def application_name
        (@application.details['application_name'] || 'cds-runner')
      end

      private

      IGNORE_FILES = %w[*.last_modified *.etag *.cached *.java-buildpack/*].join(' ')

      ARGUMENTS_PROPERTY = 'arguments'

      CLASS_PATH_PROPERTY = 'Class-Path'

      private_constant :ARGUMENTS_PROPERTY, :CLASS_PATH_PROPERTY

      def release_text()
        [
          @droplet.environment_variables.as_env_vars,
          'eval',
          'exec',
          "#{qualify_path @droplet.java_home.root, @droplet.root}/bin/java",
          '$JAVA_OPTS',
          '-jar',
          "#{application_name}.jar",
          arguments
        ].flatten.compact.join(' ')
      end

      def arguments
        @configuration[ARGUMENTS_PROPERTY]
      end

      def classpath
        cp = @spring_boot_utils.is?(@application) ? '-cp $PWD/.' : @droplet.additional_libraries.as_classpath
        ([cp] + @droplet.root_libraries.qualified_paths).join(':')
      end

      def main_class
        JavaBuildpack::Util::JavaMainUtils.main_class(@application, @configuration)
      end

      def thin_root
        @droplet.sandbox + 'repository'
      end

    end

  end
end
