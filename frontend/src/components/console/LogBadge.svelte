<!--
  ログバッジコンポーネント

  コンソールログの各種バッジを表示するための再利用可能なコンポーネント
-->
<script lang="ts">
  import { BADGE_CONFIGS, getBadgeClasses, type BadgeType } from './BadgeConfig';

  interface Props {
    type: BadgeType;
    /** novelId バッジの場合の ID */
    novelId?: string;
  }

  let { type, novelId }: Props = $props();

  const config = $derived(BADGE_CONFIGS[type]);
  const classes = $derived(getBadgeClasses(config));
  const label = $derived(type === 'novelId' && novelId ? `ID:${novelId}` : config.label);
</script>

<span class={classes} title={config.title}>
  {label}
</span>
