#!/usr/bin/env python3
"""Check required native action targets against a supplied WGP events.jsonl."""
import json, sys, hashlib
from pathlib import Path

expected = {
    'home_menu': ('NewMainFrameRightTopMenuBtn', 'showRightTopMenuBtn'),
    'home_search': ('NewMainFrameRightTopMenuBtn', 'onSearchButtonTapped'),
    'contacts_add': ('ContactsViewController', 'onAddContact'),
    'chat_back': ('BaseMsgContentViewController', 'onBackButtonClicked:'),
    'chat_detail': ('RoomContentLogicController', 'OpenDetailInfo'),
    'attachment': ('MMInputToolView', 'onAttachmentModeChangeButtonClicked:'),
    'dictation': ('MMGrowDictationIconView', 'iconClicked'),
    'send': ('MMInputToolView', 'onTapSendButton'),
    'tab': ('MMTabBar', '_buttonUp:'),
}
path = Path(sys.argv[1])
observed = {key: None for key in expected}
environment = None
for line in path.open():
    event = json.loads(line)
    if event.get('type') == 'environment':
        environment = event.get('data', {})
    if event.get('type') != 'snapshot':
        continue
    for node in event.get('nodes', []):
        for action in node.get('control', {}).get('actions', []):
            for key, (cls, selector) in expected.items():
                if observed[key] is None and action.get('targetClass') == cls and selector in action.get('touchUpInsideSelectors', []):
                    observed[key] = {'controlClass': node['class'], 'targetClass': cls, 'selector': selector,
                                     'windowRect': node.get('windowRect'), 'page': event.get('page'), 'sequence': event.get('sequence')}
report = {'baselineSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
          'wechat': (environment or {}).get('wechatVersion'), 'system': (environment or {}).get('systemVersion'),
          'actions': observed, 'allFound': all(observed.values()),
          'scope': 'matches supplied baseline bindings; does not prove new on-device dispatch success'}
print(json.dumps(report, ensure_ascii=False, indent=2))
raise SystemExit(not report['allFound'])
