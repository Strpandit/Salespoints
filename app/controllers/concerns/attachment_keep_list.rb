module AttachmentKeepList
  extend ActiveSupport::Concern

  private

  def blank_upload?(value)
    value.blank? || (value.respond_to?(:original_filename) && value.original_filename.blank?)
  end

  def uploaded_files(value)
    Array(value).reject { |file| blank_upload?(file) }
  end

  def merged_attachables(attachments, new_files, keep_ids)
    new_files = uploaded_files(new_files)
    current = attachments.to_a
    kept = keep_ids.nil? ? current : current.select { |attachment| keep_ids.include?(attachment.id.to_s) }
    return nil if new_files.empty? && kept.size == current.size

    kept.map(&:blob) + new_files
  end

  def keep_id_list(container, *keys)
    return nil unless container.respond_to?(:key?)

    key = keys.find { |k| container.key?(k) }
    return nil unless key

    Array(container[key]).map(&:to_s).reject(&:blank?)
  end
end
