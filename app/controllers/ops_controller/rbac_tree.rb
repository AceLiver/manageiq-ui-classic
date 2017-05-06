class OpsController
  class RbacTree
    include CompressedIds

    def self.build(role, role_features, edit)
      new(role, role_features, edit).build
    end

    def initialize(role, role_features, edit)
      @role = role
      @role_features = role_features
      @edit = edit
    end

    def remove_accords_suffix(name)
      name.sub(/_accords$/, '')
    end

    def build_section(section, parent_checked)
      kids = []
      node = {
        :key         => "#{@role.id ? to_cid(@role.id) : "new"}___tab_#{section.id}",
        :icon        => 'pficon pficon-folder-close',
        :title       => _(section.name),
        :tooltip     => _("%{title} Main Tab") % {:title => section.name},
        :checkable   => @edit,
        :cfmeNoClick => true
      }

      section.items.each do |item|
        if item.kind_of?(Menu::Section) # recurse for sections
          next unless Vmdb::PermissionStores.instance.can?(item.id)
          feature = build_section(item, parent_checked)
          kids.push(feature)
        else # kind_of?(Menu::Item) # add item features
          next if item.feature.nil?
          feature_name = remove_accords_suffix(item.feature)
          next unless MiqProductFeature.feature_exists?(feature_name) # FIXME: feature name? or :feature for items
          feature = rbac_features_tree_add_node(
            feature_name,
            (parent_checked || @role_features.include?(MiqProductFeature.feature_parent(feature)))
          )
          kids.push(feature) unless feature.nil?
        end
      end

      node[:children] = kids
      node[:select] = parent_checked || select_by_kids_selected(kids)

      node
    end

    def build
      root_feature = MiqProductFeature.feature_root
      root = MiqProductFeature.feature_details(root_feature)
      root_node = {
        :key         => "#{@role.id ? to_cid(@role.id) : "new"}__#{root_feature}",
        :icon        => 'pficon pficon-folder-close',
        :title       => _(root[:name]),
        :tooltip     => _(root[:description]) || _(root[:name]),
        :expand      => true,
        :cfmeNoClick => true,
        :select      => @role_features.include?(root_feature),
        :checkable   => @edit
      }

      top_nodes = []
      @all_vm_node = {
        :key         => "#{@role.id ? to_cid(@role.id) : "new"}___tab_all_vm_rules",
        :icon        => 'pficon pficon-folder-close',
        :title       => t = _("Access Rules for all Virtual Machines"),
        :tooltip     => t,
        :children    => [],
        :cfmeNoClick => true,
        :select      => root_node[:select],
        :checkable   => @edit
      }
      rbac_features_tree_add_node("all_vm_rules", @all_vm_node[:select])
      @all_vm_node[:select] = select_by_kids_selected(@all_vm_node[:children])

      Menu::Manager.each do |section|
        next if section.id == :cons && !Settings.product.consumption
        next unless Vmdb::PermissionStores.instance.can?(section.id)

        top_nodes.push(build_section(section, root_node[:select]))
      end
      top_nodes << @all_vm_node

      root_node[:children] = top_nodes
      root_node[:select] = select_by_kids_selected(top_nodes)
      root_node
    end

    def rbac_features_tree_add_node(feature, parent_checked = nil)
      details = MiqProductFeature.feature_details(feature)
      return if details[:hidden]

      kids = []
      node = {
        :key         => "#{@role.id ? to_cid(@role.id) : "new"}__#{feature}",
        :image       => ActionController::Base.helpers.image_path("100/feature_#{details[:feature_type]}.png"),
        :title       => _(details[:name]),
        :tooltip     => _(details[:description]) || _(details[:name]),
        :checkable   => @edit,
        :cfmeNoClick => true
      }
      node[:hideCheckbox] = true if details[:protected]

      MiqProductFeature.feature_children(feature).each do |f|
        feat = rbac_features_tree_add_node(f, (parent_checked || @role_features.include?(feature))) if f
        next unless feat

        # exceptional handling for named features
        if %w(image instance miq_template vm).index(f)
          @all_vm_node[:children].push(feat)
        else
          kids.push(feat)
        end
      end

      node[:children] = kids
      node[:select] = parent_checked || @role_features.include?(feature) || select_by_kids_selected(kids)
      node
    end

    private

    def select_by_kids_selected(kids)
      return false       if kids.empty?
      return true        if kids.all? { |k| k[:select] == true }
      return 'undefined' if kids.any? { |k| k[:select] }
    end
  end
end
