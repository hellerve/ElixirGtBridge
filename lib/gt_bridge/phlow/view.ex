defmodule View
  use TypedStruct

  typedstruct do
    field(:title, string(), default: "Unknown")
    field(:priority, integer(), default: 1)
    field(:view, any())
  end

  def as_dict(self) do
    %{
      title: self.title,
      priority: self.priority
    } ++ self.view.as_dict()
  end
end
