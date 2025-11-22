<template>
  <div class="flex items-center gap-2">
    <woot-switch
      v-model="isAutomaticMode"
      :disabled="!canToggle"
      @input="toggleAutomaticMode"
    />
    <label class="text-sm">
      <span class="font-medium">Automatic Mode</span>
      <span v-if="isAutomaticMode" class="text-green-600">ON</span>
      <span v-else class="text-slate-500">OFF</span>
    </label>
    <div v-if="isAutomaticMode" class="flex items-center gap-1 text-xs text-green-600">
      <fluent-icon icon="bot" size="14" />
      <span>AI responding</span>
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex';
import WootSwitch from 'dashboard/components/ui/Switch.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import alertMixin from 'shared/mixins/alertMixin';

export default {
  name: 'AutomaticModeToggle',
  components: {
    WootSwitch,
    FluentIcon,
  },
  mixins: [alertMixin],
  props: {
    conversationId: {
      type: Number,
      required: true,
    },
  },
  data() {
    return {
      isAutomaticMode: false,
      isLoading: false,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
    }),
    canToggle() {
      return !this.isLoading && this.currentChat?.meta?.assignee;
    },
  },
  watch: {
    currentChat: {
      immediate: true,
      handler(conversation) {
        if (conversation) {
          this.isAutomaticMode = conversation.additional_attributes?.automatic_mode || false;
        }
      },
    },
  },
  methods: {
    async toggleAutomaticMode(enabled) {
      if (this.isLoading) return;

      // Check if conversation has assignee
      if (!this.currentChat?.meta?.assignee) {
        this.showAlert(this.$t('CONVERSATION.AUTOMATIC_MODE.NO_ASSIGNEE'));
        this.isAutomaticMode = false;
        return;
      }

      this.isLoading = true;

      try {
        await this.$store.dispatch('toggleAutomaticMode', {
          conversationId: this.conversationId,
          enabled,
        });

        const message = enabled
          ? this.$t('CONVERSATION.AUTOMATIC_MODE.ENABLED')
          : this.$t('CONVERSATION.AUTOMATIC_MODE.DISABLED');

        this.showAlert(message);
      } catch (error) {
        this.showAlert(
          this.$t('CONVERSATION.AUTOMATIC_MODE.TOGGLE_FAILED')
        );
        // Revert toggle on error
        this.isAutomaticMode = !enabled;
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>

<style scoped lang="scss">
.text-green-600 {
  color: #059669;
}
</style>
