# Copyright 2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'spec_helper'

module Seahorse
  module Client
    describe Base do

      let(:api) {{ 'endpoint' => 'http://endpoint:123' }}

      let(:client_class) { Client.define(api: api) }

      let(:client) { client_class.new }

      describe '#config' do

        it 'returns a Configuration object' do
          expect(client.config).to be_kind_of(Configuration)
        end

        it 'contains the client api' do
          expect(client.config.api).to be(client_class.api)
        end

        it 'defaults endpoint to the api endpoint' do
          expect(client.config.endpoint).to eq(api['endpoint'])
        end

        it 'defaults ssl_default to true' do
          expect(client.config.ssl_default).to equal(true)
        end

        it 'passes constructor args to the config' do
          client = client_class.new(foo: 'bar')
          client.config.add_option(:foo)
          expect(client.config.foo).to eq('bar')
        end

      end

      describe '#build_request' do

        let(:request) { client_class.new.build_request('operation') }

        it 'returns a Request object' do
          expect(request).to be_kind_of(Request)
        end

        it 'builds a handler list from client plugins' do
          client_class.clear_plugins
          client_class.add_plugin(Plugins::Api)
          client_class.add_plugin(Plugins::NetHttp)
          client_class.add_plugin(Plugins::Endpoint)
          handlers = request.handlers.to_a
          expect(handlers).to include(NetHttp::Handler)
          expect(handlers).to include(Plugins::Endpoint::EndpointHandler)
        end

        it 'defaults the send handler to a NetHttp::Handler' do
          handlers = request.handlers.to_a
          expect(handlers).to include(NetHttp::Handler)
        end

        it 'sets the send handler if given as a client constructor option' do
          send_handler = Class.new(Handler)
          client = client_class.new(:send_handler => send_handler)
          request = client.build_request('operation')
          expect(request.handlers.to_a).to include(send_handler)
          expect(request.handlers.to_a).not_to include(NetHttp::Handler)
        end

        it 'populates the request context with the operation name' do
          request = client.build_request('operation_name')
          expect(request.context.operation_name).to eq('operation_name')
        end

        it 'stringifies the operation name' do
          request = client.build_request(:operation)
          expect(request.context.operation_name).to eq('operation')
        end

        it 'populates the request context params' do
          params = double('params')
          request = client.build_request('operation', params)
          expect(request.context.params).to be(params)
        end

        it 'defaults request context params to an empty hash' do
          request = client.build_request('operation')
          expect(request.context.params).to eq({})
        end

        it 'populates the context with the client configuration' do
          request = client.build_request('operation')
          expect(request.context.config).to be(client.config)
        end

      end

      describe '.api' do

        it 'can be set' do
          api = Model::Api.from_hash({})
          client_class = Class.new(Base)
          client_class.set_api(api)
          expect(client_class.api).to be(api)
        end

        it 'can be set as a hash, returning a Model::Api' do
          client_class = Class.new(Base)
          api = client_class.set_api({})
          expect(api).to be_kind_of(Model::Api)
          expect(api.to_hash).to eq(Model::Api.from_hash({}).to_hash)
        end

      end

      describe 'plugin methods' do

        let(:plugin_a) { Class.new }

        let(:plugin_b) { Class.new }

        describe '.add_plugin' do

          it 'adds plugins to the client' do
            client_class.add_plugin(plugin_a)
            expect(client_class.plugins).to include(plugin_a)
          end

          it 'does not add plugins to the client parent class' do
            subclass = Class.new(client_class)
            subclass.add_plugin(plugin_a)
            expect(client_class.plugins).to_not include(plugin_a)
            expect(subclass.plugins).to include(plugin_a)
          end

        end

        describe '.remove_plugin' do

          it 'removes a plugin from the client' do
            client_class.add_plugin(plugin_a)
            client_class.add_plugin(plugin_b)
            client_class.remove_plugin(plugin_a)
            expect(client_class.plugins).not_to include(plugin_a)
            expect(client_class.plugins).to include(plugin_b)
          end

          it 'does not remove plugins from the client parent class' do
            client_class.add_plugin(plugin_a)
            subclass = client_class.define
            subclass.remove_plugin(plugin_a)
            expect(client_class.plugins).to include(plugin_a)
            expect(subclass.plugins).not_to include(plugin_a)
          end

        end

        describe '.set_plugins' do

          it 'replaces existing plugins' do
            client_class.add_plugin(plugin_a)
            client_class.set_plugins([plugin_b])
            expect(client_class.plugins).to eq([plugin_b])
          end

        end

        describe '.clear_plugins' do

          it 'removes all plugins' do
            client_class.add_plugin(plugin_a)
            client_class.clear_plugins
            expect(client_class.plugins).to eq([])
          end

        end

        describe '.plugins' do

          it 'returns a list of plugins applied to the client' do
            expect(client_class.plugins).to be_kind_of(Array)
          end

          it 'returns a frozen list of plugins' do
            expect(client_class.plugins.frozen?).to eq(true)
          end

          it 'has a defualt list of plugins' do
            client_class = Class.new(Base)
            expect(client_class.plugins.to_a).to eq([
              Plugins::Api,
              Plugins::Endpoint,
              Plugins::NetHttp,
            ])
          end

          it 'replaces default plugins with the list specified in the API' do
            PluginA = plugin_a
            api = { 'plugins' => ['Seahorse::Client::PluginA'] }
            client_class = Base.define(api: api)
            expect(client_class.plugins.count).to eq(4)
            expect(client_class.plugins).to include(plugin_a)
          end

        end

        describe 'applying plugins' do

          it 'instructs plugins to #add_options' do
            plugin = double('plugin')
            plugin.stub(:add_options) { |config| config.add_option(:foo) }
            client_class.add_plugin(plugin)
            expect(client_class.new.config).to respond_to(:foo)
          end

          it 'calls plugin#add_options only if the plugin responds' do
            plugin = Object.new
            client_class.add_plugin(plugin)
            client_class.new
          end

          it 'instructs plugins to #add_handlers' do
            plugin = double('plugin')
            expect(plugin).to receive(:is_a?).twice.with(kind_of(Class)) { false }
            expect(plugin).to receive(:add_handlers).with(
              kind_of(HandlerList), kind_of(Configuration))
            client_class.add_plugin(plugin)
            client_class.new
          end

          it 'calls plugin#add_handlers only if the plugin responds' do
            plugin = Object.new
            client_class.add_plugin(plugin)
            client_class.new
          end

        end
      end
    end
  end
end
