class AddChunkUniquenessAndVectorIndex < ActiveRecord::Migration[8.1]
  def up
    # Удаляем возможные дубликаты, оставляя самый свежий чанк на позицию
    execute <<~SQL
      DELETE FROM chunks a USING chunks b
      WHERE a.content_id = b.content_id AND a.position = b.position AND a.id < b.id
    SQL

    remove_index :chunks, column: [ :content_id, :position ]
    add_index :chunks, [ :content_id, :position ], unique: true

    add_index :chunks, :embedding, using: :hnsw, opclass: :vector_cosine_ops,
              name: "index_chunks_on_embedding_hnsw"
  end

  def down
    remove_index :chunks, name: "index_chunks_on_embedding_hnsw"
    remove_index :chunks, column: [ :content_id, :position ]
    add_index :chunks, [ :content_id, :position ]
  end
end
