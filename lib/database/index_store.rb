# frozen_string_literal: true

require "digest"

class Database
  # Maintain lightweight persisted indexes for the YAML-backed Database.
  class IndexStore
    INVENTORY_NAME = "database_index"

    def initialize
      @inventory = Inventory.load(INVENTORY_NAME)
      ensure_structure!
      @dirty = false
    end

    def reconcile(database_hash)
      ensure_structure!
      fingerprint = compute_fingerprint(database_hash)
      return if @inventory["fingerprint"] == fingerprint

      reset_indexes!
      database_hash.each do |id, data|
        store_entry(id, data, mark_dirty: false)
      end
      @inventory["fingerprint"] = fingerprint
      @dirty = true
    end

    def lookup_by_toc_url(toc_url)
      return nil unless toc_url
      ids = @inventory["by_toc_url"][normalize_url(toc_url)]
      ids && ids.first
    end

    def lookup_by_title(title)
      return nil unless title
      ids = @inventory["by_title"][normalize_title(title)]
      ids && ids.first
    end

    def upsert(id, data)
      ensure_structure!
      remove(id)
      store_entry(id, data)
    end

    def delete(id, data = nil)
      ensure_structure!
      remove(id, extract_meta(id, data))
    end

    def flush
      return unless @dirty
      @inventory.save
      @dirty = false
    end

    private

    def ensure_structure!
      @inventory["by_toc_url"] ||= {}
      @inventory["by_title"] ||= {}
      @inventory["meta"] ||= {}
      @inventory["fingerprint"] ||= nil
    end

    def compute_fingerprint(database_hash)
      digest_source = database_hash.sort_by { |id, _| id }.map do |id, data|
        [
          id,
          data && data["toc_url"],
          data && data["title"],
          data && data["last_update"]
        ]
      end
      Digest::SHA256.hexdigest(Marshal.dump(digest_source))
    end

    def reset_indexes!
      @inventory["by_toc_url"].clear
      @inventory["by_title"].clear
      @inventory["meta"].clear
    end

    def store_entry(id, data, mark_dirty: true)
      id = id.to_i
      meta = {
        "toc_url" => normalize_url(data && data["toc_url"]),
        "title" => normalize_title(data && data["title"])
      }
      @inventory["meta"][id] = meta
      add_to_index(@inventory["by_toc_url"], meta["toc_url"], id)
      add_to_index(@inventory["by_title"], meta["title"], id)
      @dirty = true if mark_dirty
    end

    def remove(id, meta = nil)
      id = id.to_i
      meta ||= @inventory["meta"][id]
      return unless meta
      remove_from_index(@inventory["by_toc_url"], meta["toc_url"], id)
      remove_from_index(@inventory["by_title"], meta["title"], id)
      @inventory["meta"].delete(id)
      @dirty = true
    end

    def extract_meta(id, data)
      return @inventory["meta"][id.to_i] if @inventory["meta"].key?(id.to_i)
      {
        "toc_url" => normalize_url(data && data["toc_url"]),
        "title" => normalize_title(data && data["title"])
      }
    end

    def add_to_index(index, key, id)
      return unless key
      bucket = (index[key] ||= [])
      bucket << id unless bucket.include?(id)
    end

    def remove_from_index(index, key, id)
      return unless key
      bucket = index[key]
      return unless bucket
      bucket.delete(id)
      index.delete(key) if bucket.empty?
    end

    def normalize_url(url)
      return nil unless url
      url.to_s.strip.downcase
    end

    def normalize_title(title)
      return nil unless title
      title.to_s.strip.downcase
    end
  end
end
