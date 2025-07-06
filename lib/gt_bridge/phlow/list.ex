defmodule List
  use TypedStruct

  typedstruct do
    field(:items, function())
    field(:items_format, function(), default: fn v -> to_string(v))
    field(:accessor, function())
  end

  def data_source(self) do
    GtPhlowListDataSource(self.items, self.items_format, self.accessor)
  end

  def as_dict(self) do
    %{
      viewName: "GtPhlowListViewSpecification",
      dataTransport: 2
    }
  end
end
