<?php
/**
 * Copyright 2011 Adobe
 * All Rights Reserved.
 */
declare(strict_types=1);

namespace Magento\Email\Block\Adminhtml\Template;

<<<<<<< ours
use Exception;
use Magento\Backend\Block\Template\Context;
use Magento\Backend\Block\Widget;
use Magento\Email\Model\AbstractTemplate;
use Magento\Email\Model\Template;
use Magento\Email\Model\TemplateFactory;
use Magento\Framework\Filter\Input\MaliciousCode;
use Magento\Framework\Profiler;
use Magento\Store\Model\Store;
=======
use Magento\Email\Model\Template\Validator as TemplateValidator;
use Magento\Framework\Validation\ValidationException;
use Magento\Framework\App\ObjectManager;
>>>>>>> theirs

/**
 * Email template preview block.
 *
 * @api
 * @since 100.0.2
 */
class Preview extends Widget
{
    /**
     * @var string
     */
    private const ADMIN_RESOURCE = 'Magento_Email::template';

    /**
     * @var MaliciousCode
     */
    protected $_maliciousCode;

    /**
     * @var TemplateFactory
     */
    protected $_emailFactory;

    /**
     * @var string
     */
    protected $profilerName = 'email_template_proccessing';

    /**
<<<<<<< ours
     * @param Context $context
     * @param MaliciousCode $maliciousCode
     * @param TemplateFactory $emailFactory
=======
     * @var TemplateValidator
     */
    private $templateValidator;

    /**
     * @param \Magento\Backend\Block\Template\Context $context
     * @param \Magento\Framework\Filter\Input\MaliciousCode $maliciousCode
     * @param \Magento\Email\Model\TemplateFactory $emailFactory
>>>>>>> theirs
     * @param array $data
     * @param TemplateValidator $templateValidator
     */
    public function __construct(
<<<<<<< ours
        Context $context,
        MaliciousCode $maliciousCode,
        TemplateFactory $emailFactory,
        array $data = []
=======
        \Magento\Backend\Block\Template\Context $context,
        \Magento\Framework\Filter\Input\MaliciousCode $maliciousCode,
        \Magento\Email\Model\TemplateFactory $emailFactory,
        array $data = [],
        ?TemplateValidator $templateValidator = null
>>>>>>> theirs
    ) {
        $this->_maliciousCode = $maliciousCode;
        $this->_emailFactory = $emailFactory;
        $this->templateValidator = $templateValidator ?:
            ObjectManager::getInstance()->get(TemplateValidator::class);
        parent::__construct($context, $data);
    }

    /**
     * Prepare html output
     *
     * @return string
     * @throws Exception
     */
    protected function _toHtml()
    {
        if (!$this->_authorization->isAllowed(self::ADMIN_RESOURCE)) {
            return '';
        }

        $request = $this->getRequest();

        $storeId = $this->getAnyStoreView()->getId();
        /** @var $template Template */
        $template = $this->_emailFactory->create();

        if ($id = (int)$request->getParam('id')) {
            $template->load($id);
        } else {
            $rawText = $request->getParam('text');
            $rawText = is_string($rawText) ? $rawText : '';
            $rawStyles = $request->getParam('styles');
            $rawStyles = is_string($rawStyles) ? $rawStyles : '';
            try {
                $this->templateValidator->validate($rawText);
                if ($rawStyles !== '') {
                    $this->templateValidator->validate($rawStyles);
                }
            } catch (ValidationException $e) {
                throw new \Magento\Framework\Exception\LocalizedException(
                    __('Template content validation failed. Please review template syntax.')
                );
            }
            $template->setTemplateType($request->getParam('type'));
            $template->setTemplateText($this->_maliciousCode->filter($rawText));
            $template->setTemplateStyles($rawStyles);
        }

        Profiler::start($this->profilerName);

        $template->emulateDesign($storeId);
        $templateProcessed = $this->_appState->emulateAreaCode(
            AbstractTemplate::DEFAULT_DESIGN_AREA,
            [$template, 'getProcessedTemplate']
        );
        $template->revertDesign();
        $templateProcessed = $this->_maliciousCode->filter($templateProcessed);

        if ($template->isPlain()) {
            $templateProcessed = "<pre>" . $this->escapeHtml($templateProcessed) . "</pre>";
        }

        Profiler::stop($this->profilerName);

        return $templateProcessed;
    }

    /**
     * Get either default or any store view
     *
     * @return Store|null
     */
    protected function getAnyStoreView()
    {
        $store = $this->_storeManager->getDefaultStoreView();
        if ($store) {
            return $store;
        }
        foreach ($this->_storeManager->getStores() as $store) {
            return $store;
        }
        return null;
    }
}
