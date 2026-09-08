<?php
/**
 * Copyright © Magento, Inc. All rights reserved.
 * See COPYING.txt for license details.
 */
namespace Magento\Framework\View\Element;

use Magento\Framework\ObjectManager\ConfigInterface;
use Magento\Framework\ObjectManagerInterface;

/**
 * Creates Blocks
 *
 * @api
 * @since 100.0.2
 */
class BlockFactory
{
    /**
     * @var ObjectManagerInterface
     */
    protected $objectManager;

    /**
     * @var ConfigInterface
     */
    private $objectManagerConfig;

    /**
     * Constructor
     *
     * @param ObjectManagerInterface $objectManager
     * @param ConfigInterface|null $objectManagerConfig
     */
    public function __construct(
        ObjectManagerInterface $objectManager,
        ?ConfigInterface $objectManagerConfig = null
    ) {
        $this->objectManager = $objectManager;
        $this->objectManagerConfig = $objectManagerConfig ?:
            \Magento\Framework\App\ObjectManager::getInstance()->get(ConfigInterface::class);
    }

    /**
     * Create block
     *
     * @param string $blockName
     * @param array $arguments
     * @return \Magento\Framework\View\Element\BlockInterface
     * @throws \LogicException
     */
    public function createBlock($blockName, array $arguments = [])
    {
        $blockName = ltrim($blockName, '\\');
        $resolvedType = $this->objectManagerConfig->getInstanceType(
            $this->objectManagerConfig->getPreference($blockName)
        );
        if (!is_a($resolvedType, BlockInterface::class, true)) {
            throw new \LogicException($blockName . ' does not implement BlockInterface');
        }
        $block = $this->objectManager->create($blockName, $arguments);
        if ($block instanceof Template) {
            $block->setTemplateContext($block);
        }
        return $block;
    }
}
