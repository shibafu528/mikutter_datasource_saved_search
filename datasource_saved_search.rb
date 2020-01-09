# -*- coding: utf-8 -*-
# frozen_string_literal: true

module Plugin::DataSourceSavedSearch
  SavedSearch = Struct.new(:id, :query, :name, :slug, :service)
end

Plugin.create(:datasource_saved_search) do

  @crawl_count = Hash.new { |h, k| h[k] = gen_counter }
  @saved_searches = Hash.new

  on_period do |service|
    if service.class.slug == :twitter && @crawl_count[service].call >= UserConfig[:retrieve_interval_search]
      @crawl_count[service] = gen_counter
      refresh_for_service(service)
    end
  end

  filter_extract_datasources do |datasources|
    result = @saved_searches.values.flatten.inject(datasources) do |dss, saved_search|
      dss.merge(saved_search.slug => ["@#{saved_search.service.user_obj.idname}", _('Saved search'), saved_search.name])
    end
    [result]
  end

  def rewind_timeline(saved_search)
    type_strict saved_search => Plugin::DataSourceSavedSearch::SavedSearch
    saved_search.service.search(q: saved_search.query, count: 100).next{ |res|
      Plugin.call(:extract_receive_message, saved_search.slug, res) if res.is_a? Array
    }.trap{ |e|
      activity :system, _("保存した検索の取得中にエラーが発生しました (%{error})") % {error: e.to_s}
    }
  end

  def refresh(cache = :keep)
    Enumerator.new { |y|
      Plugin.filtering(:worlds, y)
    }.lazy.select { |world|
      world.class.slug == :twitter
    }.each { |twitter|
      refresh_for_service(twitter, cache)
    }
  end

  def refresh_for_service(service, cache = :keep)
    service.saved_searches(cache: cache).next { |res|
      next unless res

      @saved_searches[service.user_obj] = res.map do |record|
        Plugin::DataSourceSavedSearch::SavedSearch.new(record[:id],
                                                       URI.decode(record[:query]),
                                                       URI.decode(record[:name]),
                                                       :"savedsearch_#{record[:id]}",
                                                       service)
          .tap { |ss| rewind_timeline(ss) }
      end
    }.terminate
  end

  Delayer.new { refresh(true) }
end
