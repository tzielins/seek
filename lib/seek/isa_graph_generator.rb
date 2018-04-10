module Seek
  class IsaGraphNode
    attr_accessor :object, :child_count, :can_view

    def initialize(object)
      @object = object
      @child_count = 0
    end

    def can_view?
      can_view
    end
  end

  class ObjectAggregation
    include ActionView::Helpers::TextHelper

    attr_reader :object, :type, :count

    def ==(other)
      eql?(other)
    end

    def eql?(other)
      id == other.id
    end

    def hash
      id.hash
    end

    def id
      "#{@object.class.name}-#{@object.id}-#{@type}-#{@count}"
    end

    def title
      pluralize(@count, @type.to_s.humanize.singularize.downcase)
    end

    def avatar_key
      "#{@type.to_s.singularize}_avatar"
    end

    def initialize(object, type, children)
      @object = object
      @type = type
      @count = children.count
    end
  end

  class IsaGraphGenerator
    def initialize(object)
      @object = object
    end

    def generate(depth: 1, deep: false, include_parents: false, include_self: true, auth: true)
      @auth = auth
      hash = { nodes: [], edges: [] }

      depth = deep ? nil : depth

      # Parents and siblings...
      if include_parents
        parents(@object).each do |parent|
          merge_hashes(hash, descendants(parent, depth))
        end

        # All ancestors...
        merge_hashes(hash, ancestors(@object, nil))
      end

      # Self and descendants...
      merge_hashes(hash, descendants(@object, depth))

      hash[:nodes].delete_if { |n| n.object == @object } unless include_self

      hash
    end

    private

    def merge_hashes(hash1, hash2)
      hash1[:nodes] = (hash1[:nodes] + hash2[:nodes]).uniq(&:object)
      hash1[:edges] = (hash1[:edges] + hash2[:edges]).uniq
    end

    def descendants(object, max_depth = nil, depth = 0)
      traverse(:children, object, max_depth, depth)
    end

    def ancestors(object, max_depth = nil, depth = 0)
      hash = traverse(:parents, object, max_depth, depth)
      # Set child count for the parent nodes
      hash[:nodes].each do |node|
        node.child_count = children(node.object).count
      end

      hash
    end

    def traverse(method, object, max_depth = nil, depth = 0)
      node = Seek::IsaGraphNode.new(object)
      node.can_view = object.can_view? if @auth

      children = send(method, object)
      node.child_count = children.count if method == :children

      nodes = [node]
      edges = []

      if method == :children
        associations(object)[:aggregated_children].each do |type, method|
          associations = resolve_association(object, method)
          if associations.any?
            agg = Seek::ObjectAggregation.new(object, type, associations)
            agg_node = Seek::IsaGraphNode.new(agg)
            agg_node.can_view = true
            nodes << agg_node
            edges << [object, agg]
          end
        end
      end

      if max_depth.nil? || (depth < max_depth) || children.count == 1
        children.each do |child|
          hash = traverse(method, child, max_depth, depth + 1)
          nodes += hash[:nodes]
          edges += hash[:edges]
          edges << (method == :parents ? [child, object] : [object, child])
        end
      end

      { nodes: nodes, edges: edges }
    end

    def children(object)
      associations = associations(object)
      (associations[:children].map { |a| resolve_association(object, a) }.flatten +
      associations[:related].map { |a| resolve_association(object, a) }.flatten).uniq
    end

    def parents(object)
      associations(object)[:parents].map { |a| resolve_association(object, a) }.flatten.uniq
    end

    def resolve_association(object, association)
      return [] unless object.respond_to?(association)
      associations = object.send(association)
      associations = associations.respond_to?(:each) ? associations : [associations]
      associations.compact
    end

    def associations(object)
      case object
      when Programme
        {
          children: [:projects]
        }
      when Project
        {
          children: [:investigations],
          parents: [:programme]
        }
      when Investigation
        {
          children: [:studies],
          parents: [:projects],
          related: [:publications]
        }
      when Study
        {
          children: [:assays],
          parents: [:investigation],
          related: [:publications]
        }
      when Assay
        {
          children: [:data_files, :models, :sops, :publications, :documents],
          parents: [:study],
          related: [:publications],
          aggregated_children: { samples: :samples }
        }
      when Publication
        {
          parents: [:assays, :studies, :investigations, :data_files, :models, :presentations],
          related: [:events]
        }
      when DataFile, Document, Model, Sop, Sample, Presentation
        {
          parents: [:assays],
          related: [:publications, :events],
          aggregated_children: { samples: :extracted_samples },
        }
      when Event
        {
          parents: [:presentations, :publications, :data_files],
        }
      else
        { }
      end.reverse_merge!(parents: [], children: [], related: [], aggregated_children: {})
    end
  end
end
