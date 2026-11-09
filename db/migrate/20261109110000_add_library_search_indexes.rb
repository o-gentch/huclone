class AddLibrarySearchIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :contents, "to_tsvector('russian', coalesce(body, ''))", using: :gin, name: "index_contents_on_body_tsv"
    add_index :utterances, "to_tsvector('russian', text)", using: :gin, name: "index_utterances_on_text_tsv"
  end
end
