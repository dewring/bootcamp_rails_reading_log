module Displayable
  extend ActiveSupport::Concern

  class_methods do
    def display_title_limit
      60
    end
  end

  def display_title
    (title.presence || "Untitled").truncate(self.class.display_title_limit, omission: " (...)")
  end
end
