# -*- coding: utf-8 -*-
require 'erb'

module Magpie

  class Snake
    include Utils

    def self.reg(snake, target, state)
      proc{ instance_method("#{target}_#{state}").bind(snake).call}
    end

    def initialize(app, &block)
      @app = app
      @block = block
    end

    def call(env)
      state, header, body = @app.call(env)
      @block.call(self)
      @req = Rack::Request.new(env)
      @urls[@req.request_method].each { |path, lamb|
        if @req.path_info =~ Regexp.new("^#{path}$")
          body = lamb.call
          break
        end
      }
      [state, header, body]
      rescue Exception => e
      Magpie.logger.info(e.inspect + ":\n" + e.backtrace[0..8].join("\n"))
      [500, header, "500, 请查看日志,了解异常原因"]
    end

    def tongue(target, contents = { })
      @urls ||= { "GET" => { }, "POST" => { }}
      states = [contents[:states]].flatten.compact
      route("GET", target, states)
      actions = [contents[:actions]].flatten.compact
      route("POST", target, actions)
    end

    def reg(target, state)
      self.class.reg(self, target, state)
    end

    def route(method, target, states)
      routes = states.inject({ }){ |h, state|
        url_path = "/#{target}/#{state}"
        h[url_path] = reg(target, state)
        h["/#{target}"] = reg(target, state) if state.to_s == "index"
        h
      }
      @urls[method.to_s.upcase].merge!(routes)
    end

    def alipay_index
      @am = AlipayModel.new(@req.params)
      @title = "支付宝-收银台"
      render_success_or_fail
    end

    def chinabank_index
      @am = ChinabankModel.new(@req.params)
      @title = "网银在线-收银台"
      render_success_or_fail
    end

    def tenpay_index
      @am = TenpayModel.new(@req.params)
      @title = "财付通-收银台"
      render_success_or_fail
    end

    def order_pay
      return "支付失败, 缺少足够的参数" if @req.params.blank?
      case @req.params["notify_kind"]
      when "alipay", "chinabank"
        notify_res = send_notify("POST", @req.params["notify_url"], query_to_hash(@req.params["notify"]))
        method = "POST"
      when "tenpay"
        notify_res = send_notify("GET", @req.params["notify_url"], @req.params["notify"])
        method = "GET"
      end
      log_notify(method, @req.params["notify_url"], query_to_hash(@req.params["notify"]), notify_res)
      notify_res
    end

    private

    def render(file_name, options = { })
      layout = options["layout"] || "layouts/app.html.erb"
      file_path = File.join(File.dirname(__FILE__), "../..", "lib", "views", "#{file_name}.html.erb")
      layout_path = File.join(File.dirname(__FILE__), "../..", "lib", "views", layout)
      template = ERB.new(File.read(file_path))
      layout = ERB.new(File.read(layout_path))
      @yield = template.result(binding)
      layout.result(binding)
    end

    def query_to_hash(query)
      hash_params = query.split("&").inject({ }){ |h, q| qs = q.split("="); h[qs[0]] = qs[1]; h }
    end

    def render_success_or_fail
      if @am.valid?
        @dung = Dung.new(@am)
        render("success")
      else
        log_errors(@am.errors)
        render("fail")
      end
    end

  end

end
